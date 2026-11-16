// The HTTP wiring: the service's own listener (role review, see tests/Config.toml) against an HTTP
// stand-in of Python and zoho-sys-api on port 19182. Kafka is not set, as on the cluster today.

import guest_identity_integration.core;

import ballerina/http;
import ballerina/lang.array;
import ballerina/test;
import ballerina/time;

isolated int crmHits = 0;

service /py on new http:Listener(19182) {
    isolated resource function get v1/review\-cases/[string id](http:Request req) returns json|http:Unauthorized|error {
        if req.getHeader("Authorization") is error {
            return http:UNAUTHORIZED;
        }
        return {caseId: id, caseStatus: "REVIEW_OPEN", reviewer: check req.getHeader("X-Reviewer-Id")};
    }

    isolated resource function get v1/review\-cases(http:Request req) returns json =>
        {cases: [], kind: req.getQueryParamValue("kind") ?: ""};

    isolated resource function post v1/review\-cases/[string id]/decision\-preparations() returns http:Conflict =>
        {body: {code: "REVIEW_DATA_CHANGED", message: "changed on screen"}};
}

service /zoho\-sys\-api/v1 on new http:Listener(19183) {
    isolated resource function get zoho(http:Request req) returns json|error {
        lock {
            crmHits += 1;
        }
        string ids = req.getQueryParamValue("ids") ?: "";
        return {data: [{id: ids, zohoPath: check req.getHeader("zohoPath")}]};
    }

    isolated resource function put zoho() returns json =>
        {data: [{code: "SUCCESS", status: "success", details: {id: "X1", Modified_Time: "2026-11-16T12:00:00+00:00"}}]};

    isolated resource function post zoho() returns http:Response {
        http:Response r = new;
        r.statusCode = 204;
        return r;
    }
}

final http:Client api = check new ("http://127.0.0.1:19181");

isolated function signed(json ctx) returns map<string>|error {
    string c = re `=+$`.replaceAll(re `/`.replaceAll(re `\+`.replaceAll(array:toBase64(ctx.toJsonString().toBytes()), "-"), "_"), "");
    return {"X-Reviewer-Context": c, "X-Reviewer-Signature": check core:signatureOf(c, "test-secret-not-real")};
}

@test:Config {}
function healthAnswers() returns error? {
    http:Response live = check api->get("/health/live");
    test:assertEquals(live.statusCode, 200);
    http:Response ready = check api->get("/health/ready");
    test:assertEquals(ready.statusCode, 200);
    http:Response underBase = check api->get("/guest-identity-integration/v1/health/ready");
    test:assertEquals(underBase.statusCode, 200);
    http:Response liveUnderBase = check api->get("/guest-identity-integration/v1/health/live");
    test:assertEquals(liveUnderBase.statusCode, 200);
}

@test:Config {}
function reviewCaseNeedsASignedReviewer() returns error? {
    http:Response none = check api->get("/guest-identity-integration/v1/review-cases/RC-1");
    test:assertEquals(none.statusCode, 401);
    int exp = time:utcNow()[0] + 120;
    map<string> h = check signed({userId: "U-9", roles: ["IDENTITY_REVIEWER"], exp});
    http:Response ok = check api->get("/guest-identity-integration/v1/review-cases/RC-1", h);
    test:assertEquals(ok.statusCode, 200);
    json body = check ok.getJsonPayload();
    test:assertEquals(core:pick(body, "reviewer"), "U-9");
    h["X-Reviewer-Signature"] = "00";
    http:Response bad = check api->get("/guest-identity-integration/v1/review-cases/RC-1", h);
    test:assertEquals(bad.statusCode, 401);
    http:Response notJson = check api->post("/guest-identity-integration/v1/review-cases/RC-1/decisions", "x",
            check signed({userId: "U-9", roles: ["IDENTITY_REVIEWER"], exp}));
    test:assertEquals(notJson.statusCode, 400);
    http:Response unsigned = check api->post("/guest-identity-integration/v1/review-cases/RC-1/decisions", {});
    test:assertEquals(unsigned.statusCode, 401);
}

@test:Config {}
function webhookNeedsTheTokenAndKafka() returns error? {
    json rec = {eventType: "created", 'record: {"id": "G1", "Modified_Time": "2026-11-16T10:00:00+00:00"}};
    http:Response wrong = check api->post("/guest-identity-integration/v1/crm-events", rec, {"X-Webhook-Token": "nope"});
    test:assertEquals(wrong.statusCode, 401);
    http:Response noKafka = check api->post("/guest-identity-integration/v1/crm-events", rec,
            {"X-Webhook-Token": "test-webhook-token-not-real", "X-Correlation-Id": "CORR-W1"});
    test:assertEquals(noKafka.statusCode, 503, "Kafka is not set: nothing is published");
    test:assertEquals(check noKafka.getHeader("correlationId"), "CORR-W1");
}

@test:Config {}
function httpCrmReadsAndWritesThroughZohoSys() returns error? {
    HttpCrm crm = check new ({url: "http://127.0.0.1:19183"}, "/zoho-sys-api/v1/zoho");
    map<json>[] recs = check crmReadByIds(crm, "Contacts", ["A 1", "B"], ["First_Name", "Modified_Time"], "C");
    test:assertEquals(recs[0]["id"], "A 1,B");
    test:assertEquals(recs[0]["zohoPath"], "/crm/v6/Contacts");
    string modified = check crmUpdate(crm, "Contacts", "X1", {"Identity_Status": "PENDING_IDENTITY"}, "C");
    test:assertEquals(modified, "2026-11-16T12:00:00+00:00");
    [map<json>[], boolean] [rows, more] = check crmQuery(crm, "select id from Contacts where id = '1'", "C");
    test:assertEquals(rows.length(), 0);
    test:assertFalse(more);
    string|CrmError up = crmUpsert(crm, "Guest_Identities", "Global_ID", {"Global_ID": "x"}, "C");
    test:assertTrue(up is CrmError);
    HttpCrm down = check new ({url: "http://127.0.0.1:1"}, "/zoho-sys-api/v1/zoho");
    map<json>[]|CrmError failed = crmReadByIds(down, "Contacts", ["A"], ["id"], "C");
    test:assertTrue(failed is CrmError);
    if failed is CrmError {
        test:assertEquals(failed.detail().status, 0);
    }
}

@test:Config {}
function kafkaSettingsAreValidatedWithoutABroker() {
    test:assertTrue(protocolOf("sasl_ssl") is error ? false : true);
    test:assertTrue(protocolOf("SSL") !is error);
    test:assertTrue(protocolOf("PLAINTEXT") !is error);
    test:assertTrue(protocolOf("SASL_PLAINTEXT") !is error);
    test:assertTrue(protocolOf("TLS") is error);
    test:assertTrue(authOf({securityProtocol: "SSL"}) is ());
    test:assertTrue(authOf({securityProtocol: "SASL_SSL"}) is error, "SASL needs a user");
    test:assertTrue(authOf({securityProtocol: "SASL_SSL", username: "u", password: "p", saslMechanism: "MD5"}) is error);
    foreach string m in ["PLAIN", "SCRAM-SHA-256", "SCRAM-SHA-512"] {
        test:assertTrue(authOf({securityProtocol: "SASL_SSL", username: "u", password: "p", saslMechanism: m})
                is record {});
    }
    EventBus nb = busOf({});
    test:assertTrue(nb.publish("t", "k", {}) is error);
    test:assertEquals(queryOf({"q": "a b/é,x"}), "?q=a%20b%2F%C3%A9%2Cx");
}

@test:Config {}
function submitIsPassedToPythonAndItsRefusalReturned() returns error? {
    int exp = time:utcNow()[0] + 120;
    int before;
    lock {
        before = crmHits;
    }
    http:Response r = check api->post("/guest-identity-integration/v1/review-cases/RC-1/decisions",
            {action: "CONFIRM_DIFFERENT_PEOPLE", idempotencyKey: "k1", versionsShown: []},
            check signed({userId: "U-9", roles: ["IDENTITY_REVIEWER"], exp}));
    test:assertEquals(r.statusCode, 409);
    test:assertEquals(core:pick(check r.getJsonPayload(), "code"), "REVIEW_DATA_CHANGED");
    lock {
        test:assertEquals(crmHits, before, "no CRM call when Python refuses");
    }
}

@test:Config {}
function stateStoreFallsBackToMemoryOnlyWhenAllowed() returns error? {
    StateStore st = check stateOf();
    test:assertTrue(check st.tryLock("k", 5));
    test:assertFalse(check st.tryLock("k", 5));
    check st.unlock("k");
    check st.put("w", "v");
    test:assertEquals(check st.get("w"), "v");
}

@test:Config {}
function smokeRefusesWithoutKafkaSettings() {
    test:assertTrue(runKafkaSmoke({}, "") is error);
    test:assertTrue(runKafkaSmoke({bootstrapServers: ["127.0.0.1:1"], securityProtocol: "TLS"}, "") is error);
}

@test:Config {}
function workbenchBearerSignIn() returns error? {
    map<string> h = {
        "Authorization": "Bearer test-bff-token-not-real",
        "x-reviewer-id": "Z-77",
        "x-reviewer-roles": "IDENTITY_REVIEWER",
        "x-correlation-id": "wb-1"
    };
    http:Response q = check api->get("/guest-identity-integration/v1/review-cases?kind=GUARDRAIL", h);
    test:assertEquals(q.statusCode, 200);
    test:assertEquals(core:pick(check q.getJsonPayload(), "kind"), "GUARDRAIL");
    test:assertEquals(check q.getHeader("correlationId"), "wb-1");
    http:Response c = check api->get("/guest-identity-integration/v1/review-cases/RC-9", h);
    test:assertEquals(core:pick(check c.getJsonPayload(), "reviewer"), "Z-77");
    h["Authorization"] = "Bearer wrong";
    http:Response bad = check api->get("/guest-identity-integration/v1/review-cases", h);
    test:assertEquals(bad.statusCode, 401);
    http:Response hist = check api->get("/guest-identity-integration/v1/review-cases/RC-9/history",
            {"Authorization": "Bearer test-bff-token-not-real", "x-reviewer-id": "Z-77", "x-reviewer-roles": "AUDIT_REPORTING"});
    test:assertEquals(hist.statusCode, 404, "until the Python service has the history endpoint");
    http:Response asg = check api->post("/guest-identity-integration/v1/review-cases/RC-9/assignment", {assigneeId: "Z-1"},
            {"Authorization": "Bearer test-bff-token-not-real", "x-reviewer-id": "Z-77", "x-reviewer-roles": "IDENTITY_REVIEWER"});
    test:assertEquals(asg.statusCode, 403);
    http:Response cm = check api->post("/guest-identity-integration/v1/review-cases/RC-9/comments", {text: "x"},
            {"Authorization": "Bearer test-bff-token-not-real", "x-reviewer-id": "Z-77", "x-reviewer-roles": "AUDIT_REPORTING"});
    test:assertEquals(cm.statusCode, 403);
}
