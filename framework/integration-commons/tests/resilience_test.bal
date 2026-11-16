import ballerina/test;

// ---------- error status mapping (Global_Error_Handler) ----------

@test:Config {}
function knownErrorTypesKeepTheirMuleStatus() {
    test:assertEquals(statusForErrorType("BAD_REQUEST"), 400);
    test:assertEquals(statusForErrorType("GRAPHQL_QUERY"), 400);
    test:assertEquals(statusForErrorType("UNAUTHORIZED"), 401);
    test:assertEquals(statusForErrorType("EMPTY_RESPONSE"), 404);
    test:assertEquals(statusForErrorType("VALIDATION_ERROR"), 406);
    test:assertEquals(statusForErrorType("CIRCUIT_OPEN"), 503);
}

@test:Config {}
function unknownErrorTypeUsesTheDownstreamStatusOr500() {
    test:assertEquals(statusForErrorType("SOMETHING", 409), 409);
    test:assertEquals(statusForErrorType("SOMETHING"), 500);
}

@test:Config {}
function envelopeCarriesCorrelationIdAndType() {
    ErrorEnvelope e = envelopeOf(NOT_IMPLEMENTED, "The query or mutation is invalid.", "c-1");
    test:assertEquals(e.statusCode, 501);
    test:assertEquals(e.correlationId, "c-1");
    test:assertEquals(e.'error, "NOT_IMPLEMENTED");
}

// ---------- retry policy ----------

@test:Config {}
function paymentOperationsAreNeverRetried() {
    RetryPolicy policy = {count: 3};
    test:assertFalse(isRetryable(policy, "transactionCreate", TIMEOUT, 1));
    test:assertFalse(isRetryable(policy, "VALIDATECREDITCARD", CONNECTIVITY, 1));
    test:assertTrue(isRetryable(policy, "availableVoyages", TIMEOUT, 1));
}

@test:Config {}
function onlyConfiguredErrorTypesAndAttemptsAreRetried() {
    RetryPolicy policy = {count: 2};
    test:assertFalse(isRetryable(policy, "cities", BAD_REQUEST, 1));
    test:assertTrue(isRetryable(policy, "cities", BAD_GATEWAY, 2));
    test:assertFalse(isRetryable(policy, "cities", BAD_GATEWAY, 3));
    test:assertFalse(isRetryable({}, "cities", TIMEOUT, 1), "count 0 (every Mule environment today) never retries");
}

@test:Config {}
function backoffDoublesAndIsCapped() {
    RetryPolicy policy = {intervalSeconds: 2, backoffFactor: 2.0, maxIntervalSeconds: 10};
    test:assertEquals(backoffSeconds(policy, 1), 2d);
    test:assertEquals(backoffSeconds(policy, 2), 4d);
    test:assertEquals(backoffSeconds(policy, 3), 8d);
    test:assertEquals(backoffSeconds(policy, 4), 10d);
}

// ---------- circuit breaker rules ----------

@test:Config {}
function onlyConfiguredFailureTypesCount() {
    string[] types = ["TIMEOUT", "BAD_GATEWAY"];
    test:assertTrue(countsAsFailure("TIMEOUT", types));
    test:assertFalse(countsAsFailure("BAD_REQUEST", types), "a client error must not open the circuit");
}

@test:Config {}
function circuitOpensAtTheThreshold() {
    test:assertFalse(shouldOpen(4, 5));
    test:assertTrue(shouldOpen(5, 5));
    test:assertTrue(shouldOpen(6, 5));
}

@test:Config {}
function breakerWithoutStoreIsAlwaysClosed() {
    CircuitBreaker breaker = new ({dependencyName: "reservation-common-proc-api"}, (), "intg:test");
    test:assertFalse(breaker.isOpen("c-1"));
    breaker.recordFailure(TIMEOUT, "c-1");
    test:assertFalse(breaker.isOpen("c-1"));
    ErrorEnvelope body = breaker.openEnvelope("c-1");
    test:assertEquals(body.statusCode, 503);
    test:assertEquals(body.'error, "CIRCUIT_OPEN");
}

// ---------- notification ----------

@test:Config {}
function emailImportanceFollowsTheMuleRules() {
    test:assertEquals(importanceOf("SERVICE_UNAVAILABLE"), "High");
    test:assertEquals(importanceOf("RETRY_EXHAUSTED"), "High");
    test:assertEquals(importanceOf("BAD_REQUEST"), "Low");
    test:assertEquals(importanceOf("TIMEOUT"), "Normal");
}

@test:Config {}
function emailBodyHasTheEmailSysApiShape() returns error? {
    json body = emailBodyOf("reservation-mgr-exp-api", "TIMEOUT", "Timed out", "proc", {
                                                                                           toRecipients: ["a@example.com"],
                                                                                           ccRecipients: []
                                                                                       });
    json subject = check body.message.subject;
    test:assertEquals(subject, "reservation-mgr-exp-api");
    json[] to = <json[]>check body.message.toRecipients;
    test:assertEquals(to.length(), 1);
}
