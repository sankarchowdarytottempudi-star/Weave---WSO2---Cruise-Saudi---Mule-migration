import reservation_mgr_exp_api.core;

import ballerina/crypto;
import ballerina/log;

import aroya/integration_commons as commons;

// Cabin availability and prices (owner's decision 2026-11-20). The booking front end sends the
// same availability query several times at once (3x AvailableCabinCategories in 5-6 s each). For
// the read-only operations in `availabilityCacheOperations`:
//   - identical requests at the same time make one call to reservation-common-proc-api; the others
//     wait for it and get the same answer;
//   - a successful answer (2xx JSON with "data" and no GraphQL "errors") is kept for
//     `availabilityCacheSeconds` (0 = off) and shared by every copy through Redis (stateRedis),
//     with a memory copy per service copy. Errors are never kept.
// The key is everything the answer depends on: the API version, the whole GraphQL document as
// sent (query text, operation name and all variables: voyage, dates, occupancy, currency, promo
// ...), and the credential Seaware sees (X-Seaware-Authorization, else Authorization), as a hash.
// So two callers with different sessions never share an answer.

# Seconds a cabin availability / price answer is kept (0 = off: every request goes to the backend).
configurable int availabilityCacheSeconds = 60;
# GraphQL root fields that are read-only availability / price lookups and may be kept.
configurable string[] availabilityCacheOperations = ["availableCabinCategories", "availableCabins"];
# Redis for the shared cache (the platform Redis, intg-redis). Off: memory of each copy only.
configurable commons:RedisSettings stateRedis = {enabled: false};

final commons:SharedCache availabilityCache = check commons:newSharedCache(stateRedis,
        "reservation-mgr-exp-api:availability:", availabilityCacheSeconds, commonProc.timeoutSeconds + 5);
final readonly & string[] availabilityOps = availabilityCacheOperations.'map(s => s.toLowerAscii()).cloneReadOnly();

# Whether this request is answered through the availability cache.
#
# + ctx - The request
# + return - True for a read-only availability / price query
isolated function availabilityCached(RequestContext & readonly ctx) returns boolean {
    string? root = ctx.rootField;
    return availabilityCache.isOn() && root is string && availabilityOps.indexOf(root.toLowerAscii()) != ()
        && !core:isWrite(queryOf(ctx.payload));
}

# The cache key of an availability request.
#
# + ctx - The request
# + return - Hash of everything the answer depends on
isolated function availabilityKey(RequestContext & readonly ctx) returns string {
    string seawareAuth = (ctx.headers["X-Seaware-Authorization"] ?: "").trim();
    string credential = seawareAuth != "" ? "sw:" + seawareAuth : "auth:" + ctx.authorization;
    byte[] material = [...ctx.version.toBytes(), 10, ...credential.toBytes(), 10, ...ctx.body];
    return crypto:hashSha256(material).toBase16();
}

# A successful answer that may be kept: 2xx JSON with "data" and no GraphQL errors.
#
# + outcome - The backend outcome (read with asReceived = true)
# + return - The answer text, or () when it must not be kept
isolated function keepableText(Outcome outcome) returns string? {
    byte[]? raw = outcome.raw;
    if !outcome.ok || outcome.status != 200 || raw is () {
        return ();
    }
    string|error text = string:fromBytes(raw);
    if text is error {
        return ();
    }
    json|error parsed = text.fromJsonString();
    if parsed !is map<json> || !parsed.hasKey("data") || parsed["data"] == () {
        return ();
    }
    json errors = parsed["errors"];
    if errors is json[] && errors.length() > 0 || errors is map<json> {
        return ();
    }
    return text;
}

# The outcome of a kept (or shared) answer, in the form the normal path gives it.
#
# + text - The kept answer
# + asReceived - True to return the bytes untouched (auditing off)
# + return - The outcome
isolated function outcomeOfKept(string text, boolean asReceived) returns Outcome {
    if asReceived {
        return {ok: true, status: 200, body: (), raw: text.toBytes()};
    }
    return {ok: true, status: 200, body: jsonOf(text.toBytes())};
}

# Processes an availability request through the cache, with coalescing of identical requests.
# Never panics; every failure is an Outcome, as `processRequest`.
#
# + ctx - The request
# + asReceived - True to return the bytes untouched
# + return - The outcome
isolated function processAvailability(RequestContext & readonly ctx, boolean asReceived) returns Outcome {
    string key = availabilityKey(ctx);
    string? kept = availabilityCache.get(key);
    if kept is string {
        log:printInfo("Availability answered from the cache", correlationId = ctx.correlationId,
                operationName = ctx.operationName, origin = "cache");
        return outcomeOfKept(kept, asReceived);
    }
    decimal? mark = availabilityCache.lead(key);
    if mark is () {
        // an identical request is with the backend: wait for it and share its answer
        string? shared = availabilityCache.awaitShared(key);
        if shared is string {
            log:printInfo("Availability answered from the cache", correlationId = ctx.correlationId,
                    operationName = ctx.operationName, origin = "shared");
            return outcomeOfKept(shared, asReceived);
        }
        // it kept nothing (an error, or not to be kept): this request asks the backend itself
        return keptAfter(ctx, key, asReceived);
    }
    Outcome outcome = keptAfter(ctx, key, asReceived);
    // released after the answer was kept, so the waiters find it; a mark never released expires
    availabilityCache.release(key, mark);
    return outcome;
}

isolated function keptAfter(RequestContext & readonly ctx, string key, boolean asReceived) returns Outcome {
    Outcome outcome = processRequest(ctx, true);
    string? text = keepableText(outcome);
    if text is string {
        availabilityCache.put(key, text);
        return outcomeOfKept(text, asReceived);
    }
    if outcome.ok && !asReceived {
        // the normal path's form: the answer as JSON
        byte[]? raw = outcome.raw;
        if raw is byte[] {
            return {ok: true, status: outcome.status, body: jsonOf(raw), extraHeaders: outcome.extraHeaders};
        }
    }
    return outcome;
}
