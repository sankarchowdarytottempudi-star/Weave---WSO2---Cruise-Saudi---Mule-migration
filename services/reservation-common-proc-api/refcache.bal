import ballerina/crypto;
import ballerina/http;
import ballerina/log;
import ballerina/time;

import aroya/integration_commons as commons;

// Reference lists (titles, countries, ships …) answered from a cache refreshed every hour instead
// of asking Seaware each time (owner's decision 2026-11-16). Only plain successful answers are kept
// (HTTP 200, a JSON body without "errors"); a failed refresh never replaces a good entry. An entry
// older than the refresh time is still answered at once while a fresh copy is fetched in the
// background (one refresh per key at a time). Kept in Redis (stateRedis) so every copy of the service
// and every restart shares it; memory only when Redis is switched off.

# Root fields answered from the hourly cache.
configurable string[] hourlyCacheOperations = ["titles", "countries", "ships"];
# How old an entry may get before it is refreshed, in seconds.
configurable int hourlyCacheSeconds = 3600;
# Redis for the cache (same platform Redis as the other services). Off: memory only.
configurable commons:RedisSettings stateRedis = {enabled: false};

final StateStore refStore = check new (stateRedis, "reservation-common-proc-api:ref:");
final readonly & string[] hourlyOps = hourlyCacheOperations.'map(s => s.toLowerAscii()).cloneReadOnly();
isolated map<boolean> refreshing = {};

# Whether this read is answered from the hourly cache.
#
# + op - Root field of the query
# + body - Request body
# + return - True for a cached reference list
isolated function hourlyCached(string? op, byte[] body) returns boolean =>
    op is string && hourlyOps.indexOf(op.toLowerAscii()) != () && !isMutation(body);

isolated function refKey(byte[] body) returns string => crypto:hashSha256(body).toBase16();

# A kept answer, or () when there is none.
#
# + key - Cache key
# + return - [age in seconds, content type, body], or ()
isolated function refGet(string key) returns [int, string, byte[]]? {
    string?|error raw = refStore.get(key);
    if raw !is string {
        return ();
    }
    json|error entry = raw.fromJsonString();
    if entry !is map<json> {
        return ();
    }
    json at = entry["at"];
    json ctype = entry["contentType"];
    json data = entry["body"];
    if at !is int || ctype !is string || data !is string {
        return ();
    }
    int age = time:utcNow()[0] - at;
    return [age, ctype, data.toBytes()];
}

# Keeps a successful answer. Anything else is not kept.
#
# + key - Cache key
# + status - HTTP status of the answer
# + contentType - Its content type
# + data - Its body
isolated function refPut(string key, int status, string contentType, byte[] data) {
    if status != 200 {
        return;
    }
    string|error text = string:fromBytes(data);
    if text is error {
        return;
    }
    json|error parsed = text.fromJsonString();
    if parsed !is map<json> || parsed.hasKey("errors") && parsed["errors"] != () {
        return;
    }
    json entry = {at: time:utcNow()[0], contentType, body: text};
    // kept twice as long as the refresh time, so a stale entry can still be answered while refreshing
    error? e = refStore.put(key, entry.toJsonString(), hourlyCacheSeconds * 2);
    if e is error {
        log:printWarn("Reference list not kept", reason = e.message());
    }
}

isolated function cachedResponse(string correlationId, string contentType, byte[] data, string state) returns http:Response {
    http:Response r = new;
    r.statusCode = 200;
    r.setBinaryPayload(data, contentType);
    r.setHeader(commons:CORRELATION_HEADER, correlationId);
    r.setHeader("X-Cache", state);
    return r;
}

# Fetches a fresh copy in the background, one refresh per key at a time.
#
# + key - Cache key
# + body - The original request body
# + headers - Headers for the System API
isolated function refreshInBackground(string key, byte[] body, map<string> headers) {
    lock {
        if refreshing.hasKey(key) {
            return;
        }
        refreshing[key] = true;
    }
    byte[] & readonly b = body.cloneReadOnly();
    map<string> & readonly h = headers.cloneReadOnly();
    future<()> _ = start refreshNow(key, b, h);
}

isolated function refreshNow(string key, byte[] & readonly body, map<string> & readonly headers) {
    http:Response|http:ClientError reply = sysClient->post(sysApiPath, body, headers);
    if reply is http:Response {
        byte[]|http:ClientError data = reply.getBinaryPayload();
        if data is byte[] {
            refPut(key, reply.statusCode, reply.getContentType(), data);
        }
    }
    lock {
        _ = refreshing.removeIfHasKey(key);
    }
}
