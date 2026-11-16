import identity_support_exp_api.core;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/random;
import ballerina/time;
import aroya/integration_commons as commons;

const GUEST_IDENTITY = "guest-identity-proc-api";

isolated function dbConfigured() returns boolean => !core:isPlaceholderAddress(dbSystemApi.url);

isolated function jsonAnswer(int status, json body, string correlationId, map<string> extraHeaders = {})
        returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload(body);
    response.setHeader(commons:CORRELATION_HEADER, correlationId);
    foreach [string, string] [name, value] in extraHeaders.entries() {
        response.setHeader(name, value);
    }
    return response;
}

isolated function addressNotSet(string setting, string correlationId) returns http:Response =>
    commons:errorResponse(commons:envelopeOf(commons:SERVICE_UNAVAILABLE,
                    "The backend address is not set: " + setting + ".url", correlationId));

# Sends the caller's body to the Guest Identity process API and answers with what it said.
# Sent once: a repeat of an OTP or profile call would act twice.
#
# + method - POST or PUT
# + path - Path below the process API's base path; also the endpoint name of the error mapping
# + query - Query parameters to send
# + request - The caller's request (its body is passed on as it is)
# + headers - Headers to send
# + correlationId - The request's correlation id
# + return - The answer for the caller
isolated function forward(string method, string path, map<string[]> query, http:Request request,
        map<string> headers, string correlationId) returns http:Response {
    http:Response answer = forwardOnce(method, path, query, request, headers, correlationId);
    // Mule: audit record of every call (async), error record and error e-mail of every failure.
    recordCall(path, request, answer, correlationId);
    return answer;
}

isolated function forwardOnce(string method, string path, map<string[]> query, http:Request request,
        map<string> headers, string correlationId) returns http:Response {
    if core:isPlaceholderAddress(guestIdentityProcApi.url) {
        return addressNotSet("guestIdentityProcApi", correlationId);
    }
    http:Request out = new;
    byte[]|http:ClientError body = request.getBinaryPayload();
    if body is byte[] && body.length() > 0 {
        string contentType = request.getContentType();
        out.setBinaryPayload(body, contentType == "" ? "application/json" : contentType);
    }
    foreach [string, string] [name, value] in headers.entries() {
        out.setHeader(name, value);
    }
    out.setHeader(commons:CORRELATION_HEADER, correlationId);
    decimal began = time:monotonicNow();
    http:Response|http:ClientError reply =
        guestIdentityClient->execute(method, core:withQuery(guestIdentityBasePath + path, query), out);
    if reply is http:ClientError {
        string errorType = commons:errorTypeOfClientError(reply);
        log:printError("Backend call failed", correlationId = correlationId, operation = method + " " + path,
                backend = GUEST_IDENTITY, errorType = errorType, durationMs = millisSince(began));
        return jsonAnswer(500, core:plainErrorOf(errorType, "The backend could not be reached: " + GUEST_IDENTITY, ()),
                correlationId);
    }
    log:printInfo("Backend answered", correlationId = correlationId, operation = method + " " + path,
            backend = GUEST_IDENTITY, status = reply.statusCode, durationMs = millisSince(began));
    if reply.statusCode >= 400 {
        return backendError(reply, path, correlationId);
    }
    // Mule: the listener answers `vars.httpStatus default 200` and these flows never set it.
    reply.statusCode = 200;
    reply.setHeader(commons:CORRELATION_HEADER, correlationId);
    return reply;
}

# The answer for an error of the process API (Mule Global_Error_Handler): its body and status,
# `Retry-After` passed on, and - except for 429 - the mapped error when the mapping has one.
# When the mapping cannot be read, the process API's own answer is passed on unchanged.
#
# + reply - The process API's error answer
# + endpoint - Path of the operation
# + correlationId - The request's correlation id
# + return - The answer for the caller
isolated function backendError(http:Response reply, string endpoint, string correlationId) returns http:Response {
    int status = reply.statusCode;
    map<string> extra = {};
    string|http:HeaderNotFoundError retryAfter = reply.getHeader("Retry-After");
    if retryAfter is string {
        extra["Retry-After"] = retryAfter;
    }
    byte[]|http:ClientError raw = reply.getBinaryPayload();
    if raw is http:ClientError || raw.length() == 0 {
        return jsonAnswer(status, core:plainErrorOf(commons:errorTypeOfStatus(status),
                "The backend answered with an error and no detail: " + GUEST_IDENTITY, status), correlationId, extra);
    }
    if status != 429 && dbConfigured() {
        json|error rows = mappingRows(endpoint, status, correlationId);
        if rows is error {
            // The look-up is an extra: when it fails the caller still gets what the process API
            // said (a 400 stays a 400), not a 500 that hides it.
            log:printWarn("Error mapping could not be read, the process API's own error is answered",
                    correlationId = correlationId, operation = endpoint, status = status, reason = rows.message());
        }
        json? mapped = core:mappedBodyOf(rows);
        if mapped !is () {
            return jsonAnswer(status, mapped, correlationId, extra);
        }
    }
    http:Response response = new;
    response.statusCode = status;
    string contentType = reply.getContentType();
    response.setBinaryPayload(raw, contentType == "" ? "application/json" : contentType);
    response.setHeader(commons:CORRELATION_HEADER, correlationId);
    foreach [string, string] [name, value] in extra.entries() {
        response.setHeader(name, value);
    }
    return response;
}

const MAX_KEPT_MAPPINGS = 500;

# The rows of an error mapping look-up.
#
# + rows - The rows
# + at - When they were read (seconds since the epoch, the same clock on every copy)
type KeptMapping readonly & record {|
    json rows;
    decimal at;
|};

isolated map<KeptMapping> keptMappings = {};
# Keys whose fresh copy is being read right now (one background read per key at a time).
isolated map<boolean> refreshing = {};

# + began - A reading of the monotonic clock
# + return - Milliseconds since then
isolated function millisSince(decimal began) returns int => <int>((time:monotonicNow() - began) * 1000);

isolated function epochNow() returns decimal {
    time:Utc now = time:utcNow();
    return <decimal>now[0] + now[1];
}

# The error mapping of an endpoint and status. The query and the rows are the old application's
# (fetch-errors-db, maskedRequestPath + status); only when they are read changes:
#  - fresh (younger than errorMappingCacheSeconds): answered from the keep;
#  - older, up to errorMappingStaleSeconds: answered from the keep at once, a fresh copy is read in
#    the background for the next caller;
#  - not kept, or older than that: read now, as before.
# The keep is in memory and, with stateRedis on, in Redis (shared by every copy, kept over restarts).
# A look-up that fails is not kept.
#
# + endpoint - Path of the operation
# + status - The process API's status
# + correlationId - The request's correlation id
# + return - The mapping rows
isolated function mappingRows(string endpoint, int status, string correlationId) returns json|error {
    string key = status.toString() + " " + endpoint;
    if errorMappingCacheSeconds > 0 {
        KeptMapping? kept = keptMapping(key);
        if kept is KeptMapping {
            decimal age = epochNow() - kept.at;
            if age < <decimal>errorMappingCacheSeconds {
                return kept.rows;
            }
            if age < <decimal>errorMappingStaleSeconds {
                refreshInBackground(endpoint, status, key, correlationId);
                return kept.rows;
            }
        }
    }
    return readMapping(endpoint, status, key, correlationId);
}

isolated function readMapping(string endpoint, int status, string key, string correlationId) returns json|error {
    decimal began = time:monotonicNow();
    json rows = check dbCall(core:errorMappingRequestOf(endpoint, status), correlationId);
    log:printInfo("Error mapping read", correlationId = correlationId, status = status, durationMs = millisSince(began));
    if errorMappingCacheSeconds > 0 {
        keepMapping(key, {rows: rows.cloneReadOnly(), at: epochNow()});
    }
    return rows;
}

isolated function refreshInBackground(string endpoint, int status, string key, string correlationId) {
    lock {
        if refreshing.hasKey(key) {
            return;
        }
        refreshing[key] = true;
    }
    future<()> _ = start refreshMapping(endpoint, status, key, correlationId);
}

isolated function refreshMapping(string endpoint, int status, string key, string correlationId) {
    json|error rows = readMapping(endpoint, status, key, correlationId);
    if rows is error {
        log:printWarn("Error mapping could not be refreshed, the kept copy stays", correlationId = correlationId,
                status = status, reason = rows.message());
    }
    lock {
        _ = refreshing.removeIfHasKey(key);
    }
}

isolated function keptMapping(string key) returns KeptMapping? {
    lock {
        KeptMapping? kept = keptMappings[key];
        if kept is KeptMapping {
            return kept;
        }
    }
    // Another copy of the service, or this one before a restart, may have read it already.
    string?|error saved = state.get("errmap:" + key);
    if saved is string {
        json|error parsed = saved.fromJsonString();
        if parsed is map<json> && parsed["at"] is decimal|int|float {
            json at = parsed["at"];
            decimal readAt = at is decimal ? at : at is int ? <decimal>at : <decimal><float>at;
            KeptMapping entry = {rows: (parsed["rows"] ?: ()).cloneReadOnly(), at: readAt};
            rememberMapping(key, entry);
            return entry;
        }
    }
    return ();
}

isolated function keepMapping(string key, KeptMapping entry) {
    rememberMapping(key, entry);
    error? saved = state.put("errmap:" + key, {rows: entry.rows, at: entry.at}.toJsonString(), errorMappingStaleSeconds);
    if saved is error {
        log:printWarn("Error mapping not kept in Redis, memory only", reason = saved.message());
    }
}

isolated function rememberMapping(string key, KeptMapping entry) {
    lock {
        if keptMappings.length() >= MAX_KEPT_MAPPINGS {
            keptMappings.removeAll();
        }
        keptMappings[key] = entry;
    }
}

// Start-up: the error mappings of the operations without values in their path, read once into the
// keep in the background (read-only look-ups; the ones already kept are skipped).
final readonly & string[] PREFETCH_ENDPOINTS = ["/otp/generate", "/otp/verify", "/processGuestIdentity", "/guest-profiles"];
final readonly & int[] PREFETCH_STATUSES = [400, 404, 409, 410, 500, 503];

isolated function prefetchMappings() {
    if !errorMappingPrefetch || errorMappingCacheSeconds <= 0 || !dbConfigured() {
        return;
    }
    decimal began = time:monotonicNow();
    int read = 0;
    int kept = 0;
    foreach string endpoint in PREFETCH_ENDPOINTS {
        foreach int status in PREFETCH_STATUSES {
            string key = status.toString() + " " + endpoint;
            KeptMapping? have = keptMapping(key);
            if have is KeptMapping {
                // Kept already (a stale one is refreshed in the background when it is used).
                kept += 1;
                continue;
            }
            json|error rows = readMapping(endpoint, status, key, "prefetch-" + status.toString());
            if rows is error {
                log:printWarn("Error mapping prefetch stopped", reason = rows.message());
                return;
            }
            read += 1;
        }
    }
    log:printInfo("Error mappings prefetched", read = read, alreadyKept = kept, durationMs = millisSince(began));
}

// Start-up: one harmless request to this service itself - a login password for an address that
// cannot exist. It runs the whole path once (this API, the process API, the error mapping);
// nothing is written and no e-mail is sent.

const WARM_UP_IDENTIFIER = "weave-warm-up@example.invalid";
// "Ready" does not wait longer than this for the warm-up.
const decimal WARM_UP_LIMIT_SECONDS = 45;

final decimal startedAt = time:monotonicNow();
isolated boolean warm = false;

isolated function warmUpDone() {
    lock {
        warm = true;
    }
}

isolated function isReady() returns boolean {
    lock {
        if warm {
            return true;
        }
    }
    return time:monotonicNow() - startedAt > WARM_UP_LIMIT_SECONDS;
}

isolated function warmUp() {
    decimal began = time:monotonicNow();
    http:Client|error own = new ("http://localhost:" + httpPort.toString(), timeout = 30);
    int rounds = 0;
    if own is http:Client {
        foreach int attempt in 1 ... 15 {
            map<string> headers = {"source-system": "warm-up"};
            headers[commons:CORRELATION_HEADER] = "warm-up-" + attempt.toString();
            http:Response|error login = own->post(basePath + "/otp/generate",
                    {"identifier": WARM_UP_IDENTIFIER, "channel": "email", "context": "login"}, headers);
            if login is error {
                // The listener is not open yet.
                runtime:sleep(1);
                continue;
            }
            rounds += 1;
            if rounds >= 3 {
                break;
            }
        }
    }
    warmUpDone();
    log:printInfo("Warm-up finished", rounds = rounds, durationMs = millisSince(began));
}

isolated function dbCall(map<json> body, string correlationId) returns json|error {
    map<string> headers = {"Content-Type": "application/json", "Accept": "application/json"};
    headers[commons:CORRELATION_HEADER] = correlationId;
    http:Response reply = check dbSysClient->post(dbSystemPath, body.toJsonString().toBytes(), headers);
    if reply.statusCode >= 400 {
        return error("The database system API answered " + reply.statusCode.toString());
    }
    return reply.getJsonPayload();
}

isolated function randomBelow(int 'limit) returns int {
    int|random:Error value = random:createIntInRange(0, 'limit);
    return value is int ? value : 0;
}

isolated function newGuestId(string correlationId) returns http:Response {
    time:Utc now = time:utcNow();
    int millis = now[0] * 1000 + <int>(now[1] * 1000d).floor();
    int[] parts = [];
    foreach int i in 0 ..< 16 {
        parts.push(randomBelow(32));
    }
    return jsonAnswer(200, {"status": "Success", "guestId": core:ulidOf(millis, parts)}, correlationId);
}

isolated function newLoyaltyId(string correlationId) returns http:Response =>
    jsonAnswer(200, {"status": "Success", "loyaltyId": core:loyaltyIdOf(randomBelow(10000000))}, correlationId);
