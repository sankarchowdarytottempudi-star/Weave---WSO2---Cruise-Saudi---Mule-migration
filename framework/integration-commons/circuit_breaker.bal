import ballerina/log;
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

# Circuit breaker settings, one per protected dependency.
#
# + enabled - Switch the breaker off without a release (Mule `circuitBreaker.enabled`)
# + dependencyName - Name used in keys, logs and the error body
# + failureThreshold - Failures that open the circuit
# + openDurationSeconds - How long the circuit stays open; also the `Retry-After` value
# + failureWindowSeconds - The failure counter expires this long after the last failure
# + failureErrorTypes - Error types that count as failures
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
|};

# A circuit breaker backed by Redis, shared by every replica of a service.
public isolated class CircuitBreaker {
    private final CircuitBreakerSettings & readonly settings;
    private final redis:Client? store;
    private final string openKey;
    private final string failuresKey;

    # + settings - Breaker settings
    # + store - Redis client, or `()` to run without a breaker store (always closed)
    # + keyPrefix - Key prefix, for example `intg:exp-api:prod`
    public isolated function init(CircuitBreakerSettings settings, redis:Client? store, string keyPrefix) {
        self.settings = settings.cloneReadOnly();
        self.store = store;
        self.openKey = string `${keyPrefix}:cb:open:${settings.dependencyName}`;
        self.failuresKey = string `${keyPrefix}:cb:failures:${settings.dependencyName}`;
    }

    # Whether calls should be refused right now.
    #
    # + correlationId - For the log line
    # + return - `true` when the circuit is open
    public isolated function isOpen(string correlationId) returns boolean {
        redis:Client? store = self.store;
        if !self.settings.enabled || store is () {
            return false;
        }
        int|redis:Error exists = store->exists([self.openKey]);
        if exists is redis:Error {
            log:printError("Circuit breaker store check failed; allowing downstream call",
                    dependency = self.settings.dependencyName, correlationId = correlationId, 'error = exists);
            return false;
        }
        if exists > 0 {
            log:printWarn("Circuit breaker OPEN; failing fast", dependency = self.settings.dependencyName,
                    correlationId = correlationId);
            return true;
        }
        return false;
    }

    # Records a successful call: clears the failure counter and the open state.
    #
    # + correlationId - For the log line
    public isolated function recordSuccess(string correlationId) {
        redis:Client? store = self.store;
        if !self.settings.enabled || store is () {
            return;
        }
        int|redis:Error removed = store->del([self.failuresKey, self.openKey]);
        if removed is redis:Error {
            log:printError("Circuit breaker success cleanup failed", dependency = self.settings.dependencyName,
                    correlationId = correlationId, 'error = removed);
        }
    }

    # Records a failed call. Only configured error types count.
    #
    # + errorType - Error type of the failure
    # + correlationId - For the log line
    public isolated function recordFailure(string errorType, string correlationId) {
        redis:Client? store = self.store;
        if !self.settings.enabled || store is () || !countsAsFailure(errorType, self.settings.failureErrorTypes) {
            return;
        }
        int|redis:Error count = store->incr(self.failuresKey);
        if count is redis:Error {
            log:printError("Circuit breaker failure recording failed", dependency = self.settings.dependencyName,
                    correlationId = correlationId, 'error = count);
            return;
        }
        boolean|redis:Error expired = store->expire(self.failuresKey, self.settings.failureWindowSeconds);
        if expired is redis:Error {
            log:printWarn("Circuit breaker failure window not set", dependency = self.settings.dependencyName,
                    correlationId = correlationId, 'error = expired);
        }
        log:printWarn("Circuit breaker failure recorded", dependency = self.settings.dependencyName,
                failureCount = count, threshold = self.settings.failureThreshold, errorType = errorType,
                correlationId = correlationId);
        if shouldOpen(count, self.settings.failureThreshold) {
            string|redis:Error opened = store->setEx(self.openKey, errorType, self.settings.openDurationSeconds);
            if opened is redis:Error {
                log:printError("Circuit breaker could not open", dependency = self.settings.dependencyName,
                        correlationId = correlationId, 'error = opened);
                return;
            }
            log:printError("Circuit breaker OPENED", dependency = self.settings.dependencyName, failureCount = count,
                    retryAfterSeconds = self.settings.openDurationSeconds, correlationId = correlationId);
        }
    }

    # + return - Seconds to put in `Retry-After`
    public isolated function retryAfterSeconds() returns int => self.settings.openDurationSeconds;

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
                    retryAfterSeconds: self.settings.openDurationSeconds,
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
