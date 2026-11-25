import ballerina/log;
import ballerina/time;
import ballerinax/redis;

// Distributed circuit breaker, replacing reservation-mgr-exp-api/circuit-breaker.xml.
//
// Same behaviour as the Mule design (docs/CIRCUIT_BREAKER_DESIGN.md in the Mule repo):
//   - two keys per protected dependency: <prefix>:cb:failures:<dep> and <prefix>:cb:open:<dep>
//   - open key present -> fail fast with 503 and Retry-After
//   - a configured failure type increments the counter; at the threshold the open key is set
//     with a TTL of openDurationSeconds; when it expires the next call is the recovery probe
//   - a success clears both keys
//   - if Redis itself fails, the breaker fails OPEN (allows the call), so a Redis problem
//     never becomes an API outage
//
// One difference, on purpose: the counter uses Redis INCR, which is atomic. The Mule
// retrieve/increment/store sequence on Object Store could lose increments between replicas
// (noted as a known limit in the Mule design document).
//
// mode = "window" (added 2026-11-21; the default "consecutive" is the behaviour above, unchanged):
//   - opens only when failureThreshold failures happen within failureWindowSeconds (an exact sliding
//     window: the times of the last failureThreshold failures are kept in a Redis list, and the circuit
//     opens when the oldest of them is younger than the window). Successes do not reset it, so scattered
//     single failures over minutes never add up;
//   - stays open openSeconds (default openDurationSeconds), answering 503 with Retry-After;
//   - then half-open: exactly one trial call is let through (Redis SET NX; the others still get 503);
//     a success closes the circuit, a failure opens it again for openSeconds. A trial that never
//     reports back frees its place after halfOpenTrialSeconds.

# Circuit breaker settings, one per protected dependency.
#
# + enabled - Switch the breaker off without a release (Mule `circuitBreaker.enabled`)
# + dependencyName - Name used in keys, logs and the error body
# + failureThreshold - Failures that open the circuit
# + openDurationSeconds - How long the circuit stays open; also the `Retry-After` value
# + failureWindowSeconds - The failure counter expires this long after the last failure
# + failureErrorTypes - Error types that count as failures
# + mode - "consecutive" (default, the Mule behaviour) or "window" (sliding window and one half-open trial)
# + openSeconds - "window" mode: how long the circuit stays open; `()` = openDurationSeconds
# + halfOpenTrialSeconds - "window" mode: longest a half-open trial call holds its place
public type CircuitBreakerSettings record {|
    boolean enabled = true;
    string dependencyName;
    int failureThreshold = 5;
    int openDurationSeconds = 60;
    int failureWindowSeconds = 60;
    string[] failureErrorTypes = [
        "BAD_GATEWAY",
        "SERVICE_UNAVAILABLE",
        "GATEWAY_TIMEOUT",
        "CONNECTIVITY",
        "TIMEOUT",
        "INTERNAL_SERVER_ERROR"
    ];
    string mode = "consecutive";
    int? openSeconds = ();
    int halfOpenTrialSeconds = 60;
|};

# What a circuit breaker keeps between calls (Redis in the services; memory in tests).
public type BreakerStore isolated object {
    # + keys - Keys
    # + return - How many of them exist
    public isolated function exists(string[] keys) returns int|error;
    # + keys - Keys
    # + return - How many were removed
    public isolated function del(string[] keys) returns int|error;
    # + key - Key
    # + return - The value after the increment
    public isolated function incr(string key) returns int|error;
    # + key - Key
    # + seconds - Time to live
    # + return - Whether it was set
    public isolated function expire(string key, int seconds) returns boolean|error;
    # + key - Key
    # + value - Value
    # + seconds - Time to live
    # + return - An error when it could not be set
    public isolated function setEx(string key, string value, int seconds) returns error?;
    # + key - Key
    # + value - Value
    # + seconds - Time to live
    # + return - True when it was set (it did not exist)
    public isolated function setNxEx(string key, string value, int seconds) returns boolean|error;
    # Puts a value in front of a list and keeps only its first `keep` values.
    #
    # + key - Key
    # + value - Value
    # + keep - Values kept
    # + return - An error when it could not be done
    public isolated function pushKeep(string key, string value, int keep) returns error?;
    # + key - Key
    # + index - Position, 0 = first
    # + return - The value there, `()` when the list is shorter
    public isolated function at(string key, int index) returns string?|error;
};

# A BreakerStore in Redis.
public isolated class RedisBreakerStore {
    *BreakerStore;
    private final redis:Client redisClient;

    # + redisClient - Redis client
    public isolated function init(redis:Client redisClient) {
        self.redisClient = redisClient;
    }

    public isolated function exists(string[] keys) returns int|error {
        int|error result = self.redisClient->exists(keys);
        return result;
    }

    public isolated function del(string[] keys) returns int|error {
        int|error result = self.redisClient->del(keys);
        return result;
    }

    public isolated function incr(string key) returns int|error {
        int|error result = self.redisClient->incr(key);
        return result;
    }

    public isolated function expire(string key, int seconds) returns boolean|error {
        boolean|error result = self.redisClient->expire(key, seconds);
        return result;
    }

    public isolated function setEx(string key, string value, int seconds) returns error? {
        _ = check self.redisClient->setEx(key, value, seconds);
    }

    public isolated function setNxEx(string key, string value, int seconds) returns boolean|error {
        boolean|error result = self.redisClient->setNxEx(key, value, seconds);
        return result;
    }

    public isolated function pushKeep(string key, string value, int keep) returns error? {
        _ = check self.redisClient->lPush(key, [value]);
        _ = check self.redisClient->lTrim(key, 0, keep - 1);
    }

    public isolated function at(string key, int index) returns string?|error {
        string?|error result = self.redisClient->lIndex(key, index);
        return result;
    }
}

# A BreakerStore in memory (one copy only), for tests.
public isolated class MemoryBreakerStore {
    *BreakerStore;
    private final map<string> values = {};
    private final map<string[]> lists = {};
    private final map<decimal> expires = {};

    isolated function liveLocked(string key) returns boolean {
        lock {
            decimal? until = self.expires[key];
            if until is decimal && until <= epochNow() {
                _ = self.values.removeIfHasKey(key);
                _ = self.lists.removeIfHasKey(key);
                _ = self.expires.removeIfHasKey(key);
            }
            return self.values.hasKey(key) || self.lists.hasKey(key);
        }
    }

    public isolated function exists(string[] keys) returns int|error {
        string[] & readonly names = keys.cloneReadOnly();
        lock {
            int n = 0;
            foreach string k in names {
                if self.liveLocked(k) {
                    n += 1;
                }
            }
            return n;
        }
    }

    public isolated function del(string[] keys) returns int|error {
        string[] & readonly names = keys.cloneReadOnly();
        lock {
            int n = 0;
            foreach string k in names {
                if self.liveLocked(k) {
                    n += 1;
                }
                _ = self.values.removeIfHasKey(k);
                _ = self.lists.removeIfHasKey(k);
                _ = self.expires.removeIfHasKey(k);
            }
            return n;
        }
    }

    public isolated function incr(string key) returns int|error {
        lock {
            int n = self.liveLocked(key) ? check int:fromString(self.values[key] ?: "0") + 1 : 1;
            self.values[key] = n.toString();
            return n;
        }
    }

    public isolated function expire(string key, int seconds) returns boolean|error {
        lock {
            if !self.liveLocked(key) {
                return false;
            }
            self.expires[key] = epochNow() + <decimal>seconds;
            return true;
        }
    }

    public isolated function setEx(string key, string value, int seconds) returns error? {
        lock {
            self.values[key] = value;
            self.expires[key] = epochNow() + <decimal>seconds;
        }
    }

    public isolated function setNxEx(string key, string value, int seconds) returns boolean|error {
        lock {
            if self.liveLocked(key) {
                return false;
            }
            self.values[key] = value;
            self.expires[key] = epochNow() + <decimal>seconds;
            return true;
        }
    }

    public isolated function pushKeep(string key, string value, int keep) returns error? {
        lock {
            string[] list = self.liveLocked(key) ? (self.lists[key] ?: []) : [];
            list.unshift(value);
            self.lists[key] = list.length() > keep ? list.slice(0, keep) : list;
        }
    }

    public isolated function at(string key, int index) returns string?|error {
        lock {
            if !self.liveLocked(key) {
                return ();
            }
            string[] list = self.lists[key] ?: [];
            return index < list.length() ? list[index] : ();
        }
    }
}

# A circuit breaker backed by Redis, shared by every replica of a service.
public isolated class CircuitBreaker {
    private final CircuitBreakerSettings & readonly settings;
    private final BreakerStore? store;
    private final string openKey;
    private final string failuresKey;
    private final string halfOpenKey;
    private final string trialKey;
    private final boolean window;
    private final int openFor;

    # + settings - Breaker settings
    # + store - Redis client (or another BreakerStore), or `()` to run without a breaker store (always closed)
    # + keyPrefix - Key prefix, for example `intg:exp-api:prod`
    public isolated function init(CircuitBreakerSettings settings, redis:Client|BreakerStore? store, string keyPrefix) {
        self.settings = settings.cloneReadOnly();
        if store is redis:Client {
            self.store = new RedisBreakerStore(store);
        } else if store is BreakerStore {
            self.store = store;
        } else {
            self.store = ();
        }
        self.window = settings.mode == "window";
        self.openFor = self.window ? (settings.openSeconds ?: settings.openDurationSeconds) : settings.openDurationSeconds;
        self.openKey = string `${keyPrefix}:cb:open:${settings.dependencyName}`;
        // window mode keeps failure times in a list: its own key, so it never meets an old counter
        self.failuresKey = self.window ? string `${keyPrefix}:cb:failtimes:${settings.dependencyName}`
            : string `${keyPrefix}:cb:failures:${settings.dependencyName}`;
        self.halfOpenKey = string `${keyPrefix}:cb:halfopen:${settings.dependencyName}`;
        self.trialKey = string `${keyPrefix}:cb:trial:${settings.dependencyName}`;
    }

    # + return - The breaker's behaviour in words, for start-up logs
    public isolated function describe() returns string {
        if !self.settings.enabled {
            return "off";
        }
        string storeNote = self.store is () ? " (no store: always closed)" : "";
        if self.window {
            return string `window: opens at ${self.settings.failureThreshold} failures within ${self.settings.failureWindowSeconds} s, open ${self.openFor} s, then half-open with one trial call${storeNote}`;
        }
        return string `consecutive: opens at ${self.settings.failureThreshold} failures without a success (counter expires ${self.settings.failureWindowSeconds} s after the last failure), open ${self.openFor} s${storeNote}`;
    }

    # Whether calls should be refused right now.
    #
    # + correlationId - For the log line
    # + return - `true` when the circuit is open
    public isolated function isOpen(string correlationId) returns boolean {
        BreakerStore? store = self.store;
        if !self.settings.enabled || store is () {
            return false;
        }
        int|error exists = store.exists([self.openKey]);
        if exists is error {
            log:printError("Circuit breaker store check failed; allowing downstream call",
                    dependency = self.settings.dependencyName, correlationId = correlationId, 'error = exists);
            return false;
        }
        if exists > 0 {
            log:printWarn("Circuit breaker OPEN; failing fast", dependency = self.settings.dependencyName,
                    correlationId = correlationId);
            return true;
        }
        if !self.window {
            return false;
        }
        int|error half = store.exists([self.halfOpenKey]);
        if half is error || half == 0 {
            return false;
        }
        // half-open: one trial call at a time
        boolean|error trial = store.setNxEx(self.trialKey, correlationId, self.settings.halfOpenTrialSeconds);
        if trial is error {
            log:printError("Circuit breaker store check failed; allowing downstream call",
                    dependency = self.settings.dependencyName, correlationId = correlationId, 'error = trial);
            return false;
        }
        if trial {
            log:printWarn("Circuit breaker HALF-OPEN; trial call allowed", dependency = self.settings.dependencyName,
                    correlationId = correlationId);
            return false;
        }
        log:printWarn("Circuit breaker HALF-OPEN, trial call running; failing fast",
                dependency = self.settings.dependencyName, correlationId = correlationId);
        return true;
    }

    # Records a successful call: clears the failure counter and the open state.
    #
    # + correlationId - For the log line
    public isolated function recordSuccess(string correlationId) {
        BreakerStore? store = self.store;
        if !self.settings.enabled || store is () {
            return;
        }
        if self.window {
            // only a success while half-open changes anything: it closes the circuit
            int|error half = store.exists([self.halfOpenKey]);
            int|error open = store.exists([self.openKey]);
            if half is int && half > 0 && open is int && open == 0 {
                int|error cleared = store.del([self.halfOpenKey, self.trialKey, self.failuresKey]);
                if cleared is error {
                    log:printError("Circuit breaker could not close", dependency = self.settings.dependencyName,
                            correlationId = correlationId, 'error = cleared);
                    return;
                }
                log:printInfo("Circuit breaker CLOSED after a successful trial call",
                        dependency = self.settings.dependencyName, correlationId = correlationId);
            }
            return;
        }
        int|error removed = store.del([self.failuresKey, self.openKey]);
        if removed is error {
            log:printError("Circuit breaker success cleanup failed", dependency = self.settings.dependencyName,
                    correlationId = correlationId, 'error = removed);
        }
    }

    # Records a failed call. Only configured error types count.
    #
    # + errorType - Error type of the failure
    # + correlationId - For the log line
    public isolated function recordFailure(string errorType, string correlationId) {
        BreakerStore? store = self.store;
        if !self.settings.enabled || store is () || !countsAsFailure(errorType, self.settings.failureErrorTypes) {
            return;
        }
        if self.window {
            self.recordWindowFailure(store, errorType, correlationId);
            return;
        }
        int|error count = store.incr(self.failuresKey);
        if count is error {
            log:printError("Circuit breaker failure recording failed", dependency = self.settings.dependencyName,
                    correlationId = correlationId, 'error = count);
            return;
        }
        boolean|error expired = store.expire(self.failuresKey, self.settings.failureWindowSeconds);
        if expired is error {
            log:printWarn("Circuit breaker failure window not set", dependency = self.settings.dependencyName,
                    correlationId = correlationId, 'error = expired);
        }
        log:printWarn("Circuit breaker failure recorded", dependency = self.settings.dependencyName,
                failureCount = count, threshold = self.settings.failureThreshold, errorType = errorType,
                correlationId = correlationId);
        if shouldOpen(count, self.settings.failureThreshold) {
            error? opened = store.setEx(self.openKey, errorType, self.settings.openDurationSeconds);
            if opened is error {
                log:printError("Circuit breaker could not open", dependency = self.settings.dependencyName,
                        correlationId = correlationId, 'error = opened);
                return;
            }
            log:printError("Circuit breaker OPENED", dependency = self.settings.dependencyName, failureCount = count,
                    retryAfterSeconds = self.settings.openDurationSeconds, correlationId = correlationId);
        }
    }

    isolated function recordWindowFailure(BreakerStore store, string errorType, string correlationId) {
        int threshold = int:max(self.settings.failureThreshold, 1);
        int|error half = store.exists([self.halfOpenKey]);
        int|error open = store.exists([self.openKey]);
        if half is int && half > 0 && open is int && open == 0 {
            // the half-open trial failed: open again
            self.openWindow(store, errorType, correlationId, "half-open trial failed");
            return;
        }
        int nowMs = epochMillis();
        error? pushed = store.pushKeep(self.failuresKey, nowMs.toString(), threshold);
        if pushed is error {
            log:printError("Circuit breaker failure recording failed", dependency = self.settings.dependencyName,
                    correlationId = correlationId, 'error = pushed);
            return;
        }
        boolean|error expired = store.expire(self.failuresKey, self.settings.failureWindowSeconds + 5);
        if expired is error {
            log:printWarn("Circuit breaker failure window not set", dependency = self.settings.dependencyName,
                    correlationId = correlationId, 'error = expired);
        }
        string?|error oldest = store.at(self.failuresKey, threshold - 1);
        int|error oldestMs = oldest is string ? int:fromString(oldest) : -1;
        boolean full = oldestMs is int && oldestMs >= 0 && nowMs - oldestMs <= self.settings.failureWindowSeconds * 1000;
        log:printWarn("Circuit breaker failure recorded", dependency = self.settings.dependencyName,
                threshold = self.settings.failureThreshold, windowSeconds = self.settings.failureWindowSeconds,
                errorType = errorType, correlationId = correlationId);
        if full && !(open is int && open > 0) {
            self.openWindow(store, errorType, correlationId, "failure threshold reached within the window");
        }
    }

    isolated function openWindow(BreakerStore store, string errorType, string correlationId, string reason) {
        error? opened = store.setEx(self.openKey, errorType, self.openFor);
        if opened is error {
            log:printError("Circuit breaker could not open", dependency = self.settings.dependencyName,
                    correlationId = correlationId, 'error = opened);
            return;
        }
        // half-open after the open time; a forgotten half-open state ends after a day
        error? marked = store.setEx(self.halfOpenKey, "1", self.openFor + 86400);
        int|error cleared = store.del([self.trialKey, self.failuresKey]);
        if marked is error || cleared is error {
            log:printWarn("Circuit breaker half-open state not fully set", dependency = self.settings.dependencyName,
                    correlationId = correlationId);
        }
        log:printError("Circuit breaker OPENED", dependency = self.settings.dependencyName, reason = reason,
                retryAfterSeconds = self.openFor, correlationId = correlationId);
    }

    # + return - Seconds to put in `Retry-After`
    public isolated function retryAfterSeconds() returns int => self.openFor;

    # + return - The dependency name
    public isolated function dependencyName() returns string => self.settings.dependencyName;

    # The 503 body for an open circuit (same members as the Mule `downstreamErrorPayload`).
    #
    # + correlationId - The request's correlation id
    # + return - The envelope
    public isolated function openEnvelope(string correlationId) returns ErrorEnvelope {
        return envelopeOf(CIRCUIT_OPEN, "Downstream dependency is temporarily unavailable. Please retry later.",
                correlationId, targetError = {
                    dependency: self.settings.dependencyName,
                    state: "OPEN",
                    retryAfterSeconds: self.openFor,
                    message: "Downstream dependency is temporarily unavailable. Please retry later."
                });
    }
}

# Whether an error type counts against the breaker.
#
# + errorType - The failure's error type
# + failureTypes - Configured failure types
# + return - `true` if it counts
public isolated function countsAsFailure(string errorType, string[] failureTypes) returns boolean {
    return failureTypes.indexOf(errorType) !is ();
}

# Whether the failure count has reached the threshold.
#
# + count - Failures so far, including this one
# + threshold - Configured threshold
# + return - `true` when the circuit must open
public isolated function shouldOpen(int count, int threshold) returns boolean => count >= threshold;

isolated function epochMillis() returns int {
    [int, decimal] t = time:utcNow();
    return t[0] * 1000 + <int>(t[1] * 1000);
}
