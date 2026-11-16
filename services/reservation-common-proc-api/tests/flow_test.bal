import ballerina/http;
import ballerina/lang.runtime;
import ballerina/test;

import aroya/integration_commons as commons;

// Stand-ins for the Seaware System API, the Process cache and the payments Process API on
// 127.0.0.2 (made-up data only). They keep what they received so tests can check what was sent.
listener http:Listener standIns = new (18975, host = "127.0.0.2");

type Seen record {|
    string path = "";
    byte[] body = [];
    map<string> headers = {};
|};

isolated Seen seen = {};

isolated function answer(string path, http:Request req) returns http:Response {
    byte[] body = checkpanic req.getBinaryPayload();
    map<string> h = {};
    foreach string name in ["Authorization", "X-Seaware-Authorization", "client_channel", "operationName", "correlationId"] {
        string|http:HeaderNotFoundError v = req.getHeader(name);
        if v is string {
            h[name] = v;
        }
    }
    Seen now = {path: path, body: body.clone(), headers: h.clone()};
    lock {
        seen = now.clone();
    }
    string text = checkpanic string:fromBytes(body);
    if text.includes("SLOW") {
        runtime:sleep(3);
    }
    http:Response res = new;
    if text.includes("FAIL409") {
        res.statusCode = 409;
        res.setJsonPayload({message: "stand-in refused", code: "E-409"});
        return res;
    }
    res.setJsonPayload({data: {'from: path}});
    return res;
}

service / on standIns {
    isolated resource function post seaware\-sys\-api/v1/integration\-tasks(http:Request req) returns http:Response
        => answer("sys", req);
    isolated resource function post seaware\-cache\-proc\-api/v1/cache(http:Request req) returns http:Response
        => answer("cache", req);
    isolated resource function post financial\-transactions\-proc\-api/v1/process\-payment(http:Request req)
            returns http:Response => answer("payments", req);
}

isolated function lastCall() returns [string, byte[], map<string>] {
    Seen s;
    lock {
        s = seen.clone();
    }
    return [s.path, s.body, s.headers];
}

final http:Client api = check new ("http://localhost:18974/test-proc/v1", timeout = 20);

// Odd spacing, unicode and escapes: the body must reach the System API byte for byte. Regression for
// the incident of 2026-11-16: the framework's error-record interceptor emptied forwarded bodies.
const string ODD_BODY = "{ \"query\" :\"mutation Login { login { token } }\",\n\t\"variables\":{\"name\":\"Zoë Ä\"} }";

@test:Config {}
function theBodyReachesTheSystemApiByteForByte() returns error? {
    http:Response res = check api->post("/integration-tasks", ODD_BODY.toBytes(),
            {"Content-Type": "application/json", "Authorization": "Bearer caller", "X-Seaware-Authorization": "sw-1",
                "correlationId": "c-1"});
    test:assertEquals(res.statusCode, 200);
    test:assertEquals(check res.getHeader("correlationId"), "c-1");
    [string, byte[], map<string>] [path, body, headers] = lastCall();
    test:assertEquals(path, "sys");
    test:assertEquals(body, ODD_BODY.toBytes(), "the body must arrive unchanged");
    test:assertEquals(headers["Authorization"], "Bearer caller");
    test:assertEquals(headers["X-Seaware-Authorization"], "sw-1");
    test:assertEquals(headers["correlationId"], "c-1");
}

@test:Config {dependsOn: [theBodyReachesTheSystemApiByteForByte]}
function withoutCallerSignInNothingIsAdded() returns error? {
    http:Response res = check api->post("/integration-tasks", "{\"query\":\"query Titles { titles { key } }\"}".toBytes(),
            {"Content-Type": "application/json"});
    test:assertEquals(res.statusCode, 200);
    [string, byte[], map<string>] [_, _, headers] = lastCall();
    test:assertFalse(headers.hasKey("Authorization"));
    test:assertFalse(headers.hasKey("X-Seaware-Authorization"));
    test:assertTrue(headers.hasKey("correlationId"), "a correlation id is made when the caller sent none");
}

@test:Config {dependsOn: [withoutCallerSignInNothingIsAdded]}
function listsComeFromTheCache() returns error? {
    string body = "{\"query\":\"query P { availablePromotions { key } }\"}";
    http:Response res = check api->post("/integration-tasks", body.toBytes(), {"Content-Type": "application/json"});
    test:assertEquals(res.statusCode, 200);
    test:assertEquals(check res.getJsonPayload(), {data: {'from: "cache"}});
    [string, byte[], map<string>] [path, sent, headers] = lastCall();
    test:assertEquals(path, "cache");
    test:assertEquals(sent, body.toBytes());
    test:assertEquals(headers["operationName"], "availablePromotions");
}

@test:Config {dependsOn: [listsComeFromTheCache]}
function aSlowCacheFallsBackToTheLiveSource() returns error? {
    string body = "{\"query\":\"query C { cities { key } }\",\"m\":\"SLOW\"}";
    http:Response _ = check api->post("/integration-tasks", body.toBytes(), {"Content-Type": "application/json"});
    [string, byte[], map<string>] [path, sent, _] = lastCall();
    test:assertEquals(path, "sys", "after the cache failed, the live source was called");
    test:assertEquals(sent, body.toBytes());
}

@test:Config {dependsOn: [aSlowCacheFallsBackToTheLiveSource]}
function backendErrorsArePassedOnAsTheyCame() returns error? {
    http:Response res = check api->post("/integration-tasks", "{\"query\":\"query X { x }\",\"m\":\"FAIL409\"}".toBytes(),
            {"Content-Type": "application/json"});
    test:assertEquals(res.statusCode, 409);
    test:assertEquals(check res.getJsonPayload(), {message: "stand-in refused", code: "E-409"});
}

@test:Config {dependsOn: [backendErrorsArePassedOnAsTheyCame]}
function anUnreachableSystemApiAnswers502() returns error? {
    http:Response res = check api->post("/integration-tasks", "{\"query\":\"query X { x }\",\"m\":\"SLOW\"}".toBytes(),
            {"Content-Type": "application/json", "correlationId": "c-down"});
    test:assertEquals(res.statusCode, 502);
    test:assertEquals(check res.getJsonPayload(),
            {message: "Upstream reservation source was not reachable", correlationId: "c-down"});
}

const string PAYMENT = "{ \"amount\": 120.50, \"currency\":\"SAR\",\n \"reservation\":\"R-9\" }";

@test:Config {dependsOn: [anUnreachableSystemApiAnswers502]}
function paymentsAreHandedOnUnchangedWithTheCallersHeaders() returns error? {
    http:Response res = check api->post("/process-payment", PAYMENT.toBytes(),
            {"Content-Type": "application/json", "Authorization": "Bearer caller", "X-Seaware-Authorization": "sw-2",
                "client_channel": "web", "correlationId": "c-pay"});
    test:assertEquals(res.statusCode, 200);
    test:assertEquals(check res.getHeader("correlationId"), "c-pay");
    [string, byte[], map<string>] [path, body, headers] = lastCall();
    test:assertEquals(path, "payments");
    test:assertEquals(body, PAYMENT.toBytes());
    test:assertEquals(headers["Authorization"], "Bearer caller");
    test:assertEquals(headers["X-Seaware-Authorization"], "sw-2");
    test:assertEquals(headers["client_channel"], "web");
}

@test:Config {dependsOn: [paymentsAreHandedOnUnchangedWithTheCallersHeaders]}
function aRefusedPaymentIsPassedOn() returns error? {
    http:Response res = check api->post("/process-payment", "{\"m\":\"FAIL409\"}".toBytes(), {"Content-Type": "application/json"});
    test:assertEquals(res.statusCode, 409);
    test:assertEquals(check res.getJsonPayload(), {message: "stand-in refused", code: "E-409"});
}

@test:Config {dependsOn: [aRefusedPaymentIsPassedOn]}
function anUnreachablePaymentsServiceAnswers502() returns error? {
    http:Response res = check api->post("/process-payment", "{\"m\":\"SLOW\"}".toBytes(),
            {"Content-Type": "application/json", "correlationId": "c-pay-down"});
    test:assertEquals(res.statusCode, 502);
    test:assertEquals(check res.getJsonPayload(),
            {message: "The payments service was not reachable", correlationId: "c-pay-down"});
}

@test:Config {}
function rootFieldIsReadFromTheQuery() {
    test:assertEquals(rootFieldOfBody("{\"query\":\"query A { packagePromotions { key } }\"}".toBytes()), "packagePromotions");
    test:assertEquals(rootFieldOfBody("{\"other\":1}".toBytes()), ());
    test:assertEquals(rootFieldOfBody("{".toBytes()), ());
    test:assertEquals(rootFieldOfBody([0xff, 0xfe]), ());
}

@test:Config {}
function healthAnswers() returns error? {
    http:Client health = check new ("http://localhost:18974/health");
    json live = check health->get("/live");
    json ready = check health->get("/ready");
    test:assertEquals(live, {status: "UP"});
    test:assertEquals(ready, {status: "UP"});
}

@test:Config {}
function errorRecordsAreOffByDefault() {
    test:assertTrue(errorRecordSink is commons:NoopAuditSink);
}
