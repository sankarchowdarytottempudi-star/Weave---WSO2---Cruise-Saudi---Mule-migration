import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/time;

import aroya/integration_commons as commons;

// Content cache (owner's decision 2026-11-16): successful content, category and description answers
// are kept for `contentCacheSeconds` (60) and shared by every copy of the service through Redis
// (stateRedis); each copy also keeps a small memory copy so a hit costs no round trip.
//   younger than the cache time          -> answered from the cache
//   older, but within the grace time      -> answered from the cache, a fresh copy fetched in the
//                                            background (one refresh per key at a time)
//   older than cache time + grace / none  -> fetched now; concurrent identical requests share one fetch
// Only answers relayed as 200 with a body are kept; errors and empty bodies never are. The cached
// answer is exactly the relayed one: status 200, the same body bytes and the same content type.

# Seconds a content answer is served from the cache (0 = cache off).
configurable int contentCacheSeconds = 60;
# Extra seconds a cached answer may still be served while a fresh copy is fetched.
configurable int contentCacheGraceSeconds = 10;
# Memory copies kept per service copy (bytes).
configurable int contentCacheMemoryBytes = 96000000;
# Redis for the shared cache (same platform Redis as the other services). Off: memory only.
configurable commons:RedisSettings stateRedis = {enabled: false};

final StateStore contentStore = check new (stateRedis, "cms-proc-api:content:");


type Kept record {|
    int at;
    string contentType;
    byte[] body;
|};

type Memory record {|
    map<Kept & readonly> copies;
    int bytes;
|};

isolated Memory memory = {copies: {}, bytes: 0};
final decimal coalesceWaitSeconds = strapi.timeoutSeconds + 5d;
isolated map<boolean> inFlight = {};
isolated map<boolean> refreshing = {};

# A content answer through the cache.
#
# + key - Cache key: what is asked of the source (address with its query)
# + fetcher - The call to the source
# + correlationId - Correlation id
# + backend - Name of the source, for the old error answers
# + return - The caller's answer
isolated function cachedRelay(string key, isolated function () returns http:Response|http:ClientError fetcher, string correlationId, string backend) returns http:Response {
    if contentCacheSeconds <= 0 {
        return relay(fetcher(), correlationId, backend);
    }
    Kept? hit = keptOf(key);
    if hit is Kept {
        int age = time:utcNow()[0] - hit.at;
        if age < contentCacheSeconds {
            return answerOf(hit);
        }
        if age < contentCacheSeconds + contentCacheGraceSeconds {
            refreshInBackground(key, fetcher, correlationId, backend);
            return answerOf(hit);
        }
    }
    boolean leader = false;
    lock {
        if !inFlight.hasKey(key) {
            inFlight[key] = true;
            leader = true;
        }
    }
    if !leader {
        // an identical request is being fetched: wait for it and share its answer
        decimal waited = 0;
        while waited < coalesceWaitSeconds {
            runtime:sleep(0.02d);
            waited += 0.02d;
            boolean busy = true;
            lock {
                busy = inFlight.hasKey(key);
            }
            if !busy {
                break;
            }
        }
        Kept? now = keptOf(key);
        if now is Kept && time:utcNow()[0] - now.at < contentCacheSeconds + contentCacheGraceSeconds {
            return answerOf(now);
        }
        return relay(fetcher(), correlationId, backend);
    }
    http:Response out = relay(fetcher(), correlationId, backend);
    keepIfOk(key, out);
    lock {
        _ = inFlight.removeIfHasKey(key);
    }
    return out;
}

// The answer as relay() builds it for a 2xx with a body.
isolated function answerOf(Kept kept) returns http:Response {
    http:Response out = new;
    out.statusCode = 200;
    out.setBinaryPayload(kept.body);
    out.setHeader("content-type", kept.contentType);
    return out;
}

isolated function keepIfOk(string key, http:Response out) {
    if out.statusCode != 200 {
        return;
    }
    byte[]|http:ClientError body = out.getBinaryPayload();
    string|http:HeaderNotFoundError ctype = out.getHeader("content-type");
    if body !is byte[] || body.length() == 0 || ctype !is string {
        return;
    }
    Kept & readonly kept = {at: time:utcNow()[0], contentType: ctype, body: body.cloneReadOnly()};
    remember(key, kept);
    string|error text = string:fromBytes(body);
    if text is error {
        return;     // not text: kept in memory only
    }
    // value: "<at>\n<content type>\n<body>"; kept a little longer than the grace time
    error? e = contentStore.put(key, kept.at.toString() + "\n" + ctype + "\n" + text,
            contentCacheSeconds + contentCacheGraceSeconds + 5);
    if e is error {
        log:printWarn("Content answer not kept in Redis", reason = e.message());
    }
}

isolated function keptOf(string key) returns Kept? {
    lock {
        (Kept & readonly)? mine = memory.copies[key];
        if mine is Kept && time:utcNow()[0] - mine.at < contentCacheSeconds {
            return mine;
        }
    }
    string?|error raw = contentStore.get(key);
    if raw !is string {
        lock {
            (Kept & readonly)? mine = memory.copies[key];
            if mine is Kept {
                return mine;
            }
        }
        return ();
    }
    int? first = raw.indexOf("\n");
    if first is () {
        return ();
    }
    int? second = raw.indexOf("\n", first + 1);
    if second is () {
        return ();
    }
    int|error at = int:fromString(raw.substring(0, first));
    if at is error {
        return ();
    }
    Kept & readonly kept = {at, contentType: raw.substring(first + 1, second),
        body: raw.substring(second + 1).toBytes().cloneReadOnly()};
    lock {
        (Kept & readonly)? mine = memory.copies[key];
        if mine is Kept && mine.at >= kept.at {
            return mine;
        }
    }
    remember(key, kept);
    return kept;
}

isolated function remember(string key, Kept & readonly kept) {
    lock {
        (Kept & readonly)? old = memory.copies[key];
        if old is Kept {
            memory.bytes -= old.body.length();
        }
        if memory.bytes + kept.body.length() > contentCacheMemoryBytes {
            // keep it simple: start over when the memory budget is reached
            memory.copies.removeAll();
            memory.bytes = 0;
        }
        memory.copies[key] = kept;
        memory.bytes += kept.body.length();
    }
}

isolated function refreshInBackground(string key, isolated function () returns http:Response|http:ClientError fetcher, string correlationId, string backend) {
    lock {
        if refreshing.hasKey(key) {
            return;
        }
        refreshing[key] = true;
    }
    future<()> _ = start refreshNow(key, fetcher, correlationId, backend);
}

isolated function refreshNow(string key, isolated function () returns http:Response|http:ClientError fetcher, string correlationId, string backend) {
    keepIfOk(key, relay(fetcher(), correlationId, backend));
    lock {
        _ = refreshing.removeIfHasKey(key);
    }
}

# Where the cache lives, for the start-up line.
#
# + return - "Redis" or "memory", or "off"
isolated function contentCacheState() returns string =>
    contentCacheSeconds <= 0 ? "off" : contentStore.location() + ", " + contentCacheSeconds.toString() + " s";
