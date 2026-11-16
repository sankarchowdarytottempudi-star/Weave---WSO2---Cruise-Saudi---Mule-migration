import ballerina/http;
import ballerina/test;

// ---------- correlation and headers ----------

@test:Config {}
function callerCorrelationIdIsKeptOrCreated() {
    http:Request withId = new;
    withId.setHeader("correlationId", "c-42");
    test:assertEquals(correlationIdOf(withId), "c-42");
    string generated = correlationIdOf(new http:Request());
    test:assertEquals(generated.length(), 36, "a UUID when the caller sent none");
}

@test:Config {}
function missingHeadersAreNil() {
    http:Request r = new;
    r.setHeader("client_id", "abc");
    test:assertEquals(headerOf(r, "client_id"), "abc");
    test:assertEquals(headerOf(r, "absent"), ());
}

@test:Config {}
function onlyPassThroughHeadersAndNonBlankExtrasAreForwarded() {
    http:Request r = new;
    r.setHeader("Authorization", "Bearer t");
    r.setHeader("client_channel", "mobile");
    r.setHeader("cookie", "never-forwarded");
    map<string> h = forwardHeaders(r, "c-1", {"client_version": "v2", "x-empty": "", "x-nil": ()});
    test:assertEquals(h["Authorization"], "Bearer t");
    test:assertEquals(h["client_channel"], "mobile");
    test:assertEquals(h["client_version"], "v2");
    test:assertEquals(h["correlationId"], "c-1");
    test:assertFalse(h.hasKey("cookie"));
    test:assertFalse(h.hasKey("x-empty"));
    test:assertFalse(h.hasKey("x-nil"));
}

// ---------- error responses ----------

@test:Config {}
function errorResponseCarriesStatusBodyAndHeaders() returns error? {
    http:Response res = errorResponse(envelopeOf(CIRCUIT_OPEN, "down", "c-9"), {"Retry-After": "60"});
    test:assertEquals(res.statusCode, 503);
    test:assertEquals(check res.getHeader("Retry-After"), "60");
    test:assertEquals(check res.getHeader("correlationId"), "c-9");
    json body = check res.getJsonPayload();
    test:assertEquals(check body.'error, "CIRCUIT_OPEN");
}

@test:Config {}
function downstreamStatusesMapToMuleErrorTypes() {
    test:assertEquals(errorTypeOfStatus(400), "BAD_REQUEST");
    test:assertEquals(errorTypeOfStatus(401), "UNAUTHORIZED");
    test:assertEquals(errorTypeOfStatus(404), "NOT_FOUND");
    test:assertEquals(errorTypeOfStatus(500), "INTERNAL_SERVER_ERROR");
    test:assertEquals(errorTypeOfStatus(502), "BAD_GATEWAY");
    test:assertEquals(errorTypeOfStatus(503), "SERVICE_UNAVAILABLE");
    test:assertEquals(errorTypeOfStatus(504), "GATEWAY_TIMEOUT");
    test:assertEquals(errorTypeOfStatus(418), "BAD_REQUEST");
    test:assertEquals(errorTypeOfStatus(599), "INTERNAL_SERVER_ERROR");
}

@test:Config {}
function unreachableHostIsConnectivity() returns error? {
    http:Client c = check newDownstreamClient({url: "http://127.0.0.1:1", timeoutSeconds: 2});
    http:Response|http:ClientError r = c->get("/");
    if r is http:Response {
        test:assertFail("nothing listens on port 1");
    }
    test:assertEquals(errorTypeOfClientError(r), "CONNECTIVITY");
}

@test:Config {}
function clientsBuildForEveryTlsMode() returns error? {
    _ = check newDownstreamClient({url: "https://example.com", http2: true});
    _ = check newDownstreamClient({url: "https://example.com", tlsValidation: false});
    _ = check newDownstreamClient({url: "http://example.com"});
}

// ---------- sinks and notifier when switched off ----------

@test:Config {}
function disabledKafkaGivesANoopSink() returns error? {
    AuditSink sink = check newAuditSink({auditEnabled: false, errorEnabled: false});
    test:assertTrue(sink is NoopAuditSink);
    sink.audit("c-1", {}, {});
    sink.failure("c-1", {}, {});
}

@test:Config {}
function disabledNotifierSendsNothing() returns error? {
    ErrorNotifier n = check new ({enabled: false});
    n.notify("api", "TIMEOUT", "d", "x", "c-1");
}

@test:Config {}
function redisSwitchedOffGivesNoClient() returns error? {
    test:assertEquals(check newRedisClient({enabled: false}, "test"), ());
}

@test:Config {}
function breakerSwitchedOffNeverOpens() {
    CircuitBreaker b = new ({enabled: false, dependencyName: "d", failureThreshold: 1}, (), "intg:test");
    b.recordFailure("TIMEOUT", "c-1");
    b.recordSuccess("c-1");
    test:assertFalse(b.isOpen("c-1"));
    test:assertEquals(b.retryAfterSeconds(), 60);
    test:assertEquals(b.dependencyName(), "d");
}
