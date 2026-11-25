import ballerina/lang.runtime;

// Retry policy, replacing http-error-retrySub_Flow and resilience.nonRetryableOperations.
// The Mule sub-flow re-entered the failing flow by name with a decremented counter; here the
// call is wrapped in a loop with exponential backoff, and payment-sensitive operations are
// never retried (no duplicate side effects).

# Retry settings for a downstream.
#
# + count - Extra attempts after the first (Mule `error.httpRetryCount`, 0 in every environment today)
# + intervalSeconds - Wait before the first retry (Mule `error.httpRetryFrequency` / 1000)
# + backoffFactor - Multiplier applied to the wait after each retry
# + maxIntervalSeconds - Upper bound for the wait
# + retryOn - Error types that are retried (Mule `error.httpErrorTypes`)
# + nonRetryableOperations - GraphQL root fields that are never retried
public type RetryPolicy record {|
    int count = 0;
    decimal intervalSeconds = 5;
    float backoffFactor = 2.0;
    decimal maxIntervalSeconds = 20;
    string[] retryOn = ["BAD_GATEWAY", "CONNECTIVITY", "TIMEOUT"];
    string[] nonRetryableOperations = [
        "transactionCreate",
        "transactionCreateOrAccept",
        "transactionAccept",
        "transactionVoid",
        "validateCreditCard"
    ];
|};

# Whether a failed attempt may be retried.
#
# + policy - The retry policy
# + operation - The request's GraphQL root field (case-insensitive)
# + errorType - The failure's error type
# + attempt - Attempts made so far (1 after the first call)
# + return - `true` if another attempt is allowed
public isolated function isRetryable(RetryPolicy policy, string? operation, string errorType, int attempt) returns boolean {
    if attempt > policy.count {
        return false;
    }
    if operation is string {
        string op = operation.toLowerAscii();
        foreach string blocked in policy.nonRetryableOperations {
            if blocked.toLowerAscii() == op {
                return false;
            }
        }
    }
    return policy.retryOn.indexOf(errorType) !is ();
}

# Wait before retry number `attempt` (1-based).
#
# + policy - The retry policy
# + attempt - The attempt that just failed
# + return - Seconds to wait
public isolated function backoffSeconds(RetryPolicy policy, int attempt) returns decimal {
    decimal delay = policy.intervalSeconds;
    int i = 1;
    while i < attempt {
        delay = delay * <decimal>policy.backoffFactor;
        i += 1;
    }
    return delay > policy.maxIntervalSeconds ? policy.maxIntervalSeconds : delay;
}

# Sleeps for the backoff of `attempt`.
#
# + policy - The retry policy
# + attempt - The attempt that just failed
public isolated function waitBeforeRetry(RetryPolicy policy, int attempt) {
    runtime:sleep(backoffSeconds(policy, attempt));
}
