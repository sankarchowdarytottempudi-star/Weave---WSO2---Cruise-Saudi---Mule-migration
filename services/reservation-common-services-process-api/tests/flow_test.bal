import ballerina/http;
import ballerina/test;

import aroya/integration_commons as commons;

// The operation as callers use it, against the stand-ins in token_test.bal.
final http:Client api = check new ("http://localhost:18964/test-api/v1", timeout = 20);

// A body with odd spacing, a unicode name and escapes: it must reach the System API byte for byte
// (regression for the incident of 2026-11-16, when a framework interceptor emptied forwarded bodies).
const string ODD_BODY = "{ \"query\" :\"query Reservation { reservation(key: \\\"R-1\\\") { key } }\",\n\t\"variables\":{\"name\":\"Zoë Ä\"} }";

@test:Config {dependsOn: [aRefusedTokenIsReplaced]}
function bodyAndCallerSignInGoThroughUnchanged() returns error? {
    http:Response res = check api->post("/integration-tasks", ODD_BODY.toBytes(),
            {"Content-Type": "application/json", "Authorization": "Bearer caller", "X-Seaware-Authorization": "sw-1",
                "correlationId": "c-odd"});
    test:assertEquals(res.statusCode, 200);
    test:assertEquals(check res.getHeader("correlationId"), "c-odd");
    [string, byte[], map<string>] [path, body, headers] = lastCall();
    test:assertEquals(path, "sys");
    test:assertEquals(body, ODD_BODY.toBytes(), "the body must arrive unchanged");
    test:assertEquals(headers["Authorization"], "Bearer caller");
    test:assertEquals(headers["X-Seaware-Authorization"], "sw-1");
    test:assertEquals(headers["correlationId"], "c-odd");
}

@test:Config {dependsOn: [bodyAndCallerSignInGoThroughUnchanged]}
function listsComeFromTheCache() returns error? {
    string body = "{\"query\":\"query AvailableVoyages { availableVoyages { key } }\"}";
    http:Response res = check api->post("/integration-tasks", body.toBytes(), {"Content-Type": "application/json"});
    test:assertEquals(res.statusCode, 200);
    test:assertEquals(check res.getJsonPayload(), {data: {'from: "cache"}});
    [string, byte[], map<string>] [path, sent, headers] = lastCall();
    test:assertEquals(path, "cache");
    test:assertEquals(sent, body.toBytes());
    test:assertEquals(headers["operationName"], "availableVoyages");
    test:assertTrue(res.getHeader("correlationId") is string);
}

@test:Config {dependsOn: [listsComeFromTheCache]}
function aSlowCacheFallsBackToTheLiveSource() returns error? {
    // the cache answers after 3 s, the cache client waits 1 s: the live source answers instead
    string body = "{\"query\":\"query Cities { cities { key } }\",\"marker\":\"SLOW-cache\"}";
    http:Response res = check api->post("/integration-tasks", body.toBytes(),
            {"Content-Type": "application/json", "Authorization": "Bearer caller"});
    // the live source gets the same marker and is slow too, but its client waits longer (2 s timeout
    // answers 502): the fall-through itself is what is checked here
    test:assertTrue(res.statusCode == 200 || res.statusCode == 502);
    [string, byte[], map<string>] [path, _, _] = lastCall();
    test:assertEquals(path, "sys", "after the cache failed, the live source was called");
}

@test:Config {dependsOn: [aSlowCacheFallsBackToTheLiveSource]}
function withoutCallerSignInTheApiSignsInItself() returns error? {
    check state.remove(SEAWARE_TOKEN_KEY);
    int before = loginCount();
    http:Response res = check api->post("/integration-tasks", "{\"query\":\"query Titles { titles { key } }\"}".toBytes(),
            {"Content-Type": "application/json"});
    test:assertEquals(res.statusCode, 200);
    test:assertEquals(loginCount(), before + 1);
    [string, byte[], map<string>] [_, _, headers] = lastCall();
    test:assertEquals(headers["Authorization"], check state.get(SEAWARE_TOKEN_KEY));
    // a second call reuses the kept token
    http:Response _ = check api->post("/integration-tasks", "{\"query\":\"query Titles { titles { key } }\"}".toBytes(),
            {"Content-Type": "application/json"});
    test:assertEquals(loginCount(), before + 1);
}

@test:Config {dependsOn: [withoutCallerSignInTheApiSignsInItself]}
function aRefusedKeptTokenIsRenewedAndTheCallRepeatedOnce() returns error? {
    check state.put(SEAWARE_TOKEN_KEY, "stale-token", 600);
    int before = loginCount();
    http:Response res = check api->post("/integration-tasks", "{\"query\":\"query Titles { titles { key } }\"}".toBytes(),
            {"Content-Type": "application/json"});
    test:assertEquals(res.statusCode, 200, "after a 401 the token is renewed and the call made again");
    test:assertEquals(loginCount(), before + 1);
    test:assertNotEquals(check state.get(SEAWARE_TOKEN_KEY), "stale-token");
}

@test:Config {dependsOn: [aRefusedKeptTokenIsRenewedAndTheCallRepeatedOnce]}
function aFailedSignInStillMakesTheCallWithoutToken() returns error? {
    check state.remove(SEAWARE_TOKEN_KEY);
    setLoginWithoutToken(true);
    http:Response res = check api->post("/integration-tasks", "{\"query\":\"query Titles { titles { key } }\"}".toBytes(),
            {"Content-Type": "application/json"});
    setLoginWithoutToken(false);
    test:assertEquals(res.statusCode, 200);
    [string, byte[], map<string>] [path, _, headers] = lastCall();
    test:assertEquals(path, "sys");
    test:assertFalse(headers.hasKey("Authorization"));
}

@test:Config {dependsOn: [aFailedSignInStillMakesTheCallWithoutToken]}
function backendErrorsArePassedOnAsTheyCame() returns error? {
    http:Response res = check api->post("/integration-tasks", "{\"query\":\"query X { x }\",\"m\":\"FAIL500\"}".toBytes(),
            {"Content-Type": "application/json", "Authorization": "Bearer caller"});
    test:assertEquals(res.statusCode, 500);
    test:assertEquals(check res.getJsonPayload(), {message: "stand-in failure", code: "E-500"});
}

@test:Config {dependsOn: [backendErrorsArePassedOnAsTheyCame]}
function anUnreachableBackendAnswers502() returns error? {
    http:Response res = check api->post("/integration-tasks", "{\"query\":\"query X { x }\",\"m\":\"SLOW\"}".toBytes(),
            {"Content-Type": "application/json", "Authorization": "Bearer caller", "correlationId": "c-down"});
    test:assertEquals(res.statusCode, 502);
    test:assertEquals(check res.getJsonPayload(),
            {message: "Upstream reservation source was not reachable", correlationId: "c-down"});
}

@test:Config {dependsOn: [anUnreachableBackendAnswers502]}
function aBodyThatIsNotJsonIsForwardedAsItIs() returns error? {
    http:Response res = check api->post("/integration-tasks", "not json at all".toBytes(),
            {"Content-Type": "application/json", "Authorization": "Bearer caller"});
    test:assertEquals(res.statusCode, 200);
    [string, byte[], map<string>] [path, body, _] = lastCall();
    test:assertEquals(path, "sys");
    test:assertEquals(body, "not json at all".toBytes());
}

@test:Config {}
function rootFieldIsReadFromTheQuery() {
    test:assertEquals(rootFieldOfBody("{\"query\":\"query A { availableVoyages { key } }\"}".toBytes()), "availableVoyages");
    test:assertEquals(rootFieldOfBody("{\"other\":1}".toBytes()), ());
    test:assertEquals(rootFieldOfBody("[1,".toBytes()), ());
    test:assertEquals(rootFieldOfBody([0xff, 0xfe, 0xfd]), ());
}

@test:Config {}
function healthAnswers() returns error? {
    http:Client health = check new ("http://localhost:18964/health");
    json live = check health->get("/live");
    json ready = check health->get("/ready");
    test:assertEquals(live, {status: "UP"});
    test:assertEquals(ready, {status: "UP"});
}

@test:Config {}
function errorRecordsAreOffByDefault() {
    // off: the request interceptor never reads a body (the operation tests above prove bodies arrive unchanged)
    test:assertTrue(errorRecordSink is commons:NoopAuditSink);
}
