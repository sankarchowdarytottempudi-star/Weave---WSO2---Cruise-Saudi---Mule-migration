import ballerina/test;

final CallFacts FACTS = {correlationId: "c-1", operationName: "generate", operationType: "", clientIp: "198.51.100.7",
    authorization: "Bearer abc.def", endpoint: "/otp/generate", requestPayload: {"identifier": "a@example.invalid"}};

@test:Config {}
function auditRecordHasEveryMuleField() {
    map<json> r = auditRecordOf(FACTS, {"status": "ACTIVE"}, "2026-11-16T00:00:00Z");
    foreach string k in ["session_id", "auth_token", "mule_correlation_id", "step_name", "source_api", "target_system",
            "request_method", "endpoint_url", "graphql_operation_name", "request_headers", "request_payload",
            "response_status_code", "response_headers", "response_payload", "status", "replayable", "retry_count",
            "error_message", "created_at"] {
        test:assertTrue(r.hasKey(k), k);
    }
    test:assertEquals(r["status"], "SUCCESS");
    test:assertEquals(r["target_system"], "otp");
    test:assertEquals(r["source_api"], "identity-support-exp-api");
    test:assertEquals(r["request_method"], "POST");
    json h = r["request_headers"];
    test:assertEquals(h is map<json> ? h["authorization"] : (), "MASKED");
    test:assertEquals(h is map<json> ? h["operationType"] : (), "UNKNOWN");
}

@test:Config {}
function theTokenIsNeverInARecord() {
    map<json> r = auditRecordOf(FACTS, {}, "t");
    test:assertFalse(r.toJsonString().includes("abc.def"));
    test:assertTrue((<string>r["session_id"]).startsWith("sha256:"));
    test:assertEquals(r["session_id"], r["auth_token"]);
    test:assertEquals(sessionIdOf("", (), false), "UNKNOWN");
    // Login: the session is the token of the answer (fingerprinted)
    test:assertEquals(sessionIdOf("", "tok", true), sessionIdOf("Bearer tok", (), false));
}

@test:Config {}
function errorRecordAndReplayable() {
    CallFacts store = FACTS.clone();
    store.operationName = "storeReservation";
    CallFacts login = FACTS.clone();
    login.operationName = "Login";
    map<json> r = errorRecordOf(store, 503, {"message": "down"}, "down", "t");
    test:assertEquals(r["status"], "FAILED");
    test:assertEquals(r["response_status_code"], 503);
    test:assertEquals(r["replayable"], true);
    test:assertEquals(errorRecordOf(FACTS, 500, {}, "", "t")["replayable"], false);
    test:assertEquals(errorRecordOf(FACTS, 500, {}, "", "t")["error_message"], "UNKNOWN ERROR");
    test:assertEquals(errorRecordOf(login, 401, {}, "x", "t")["session_id"], "UNKNOWN");
}

@test:Config {}
function errorMailAsMule() {
    json m = errorMailOf("uat", "identity-support-exp-api", "SERVICE_UNAVAILABLE", "d", "x", "to@example.invalid",
            "cc@example.invalid", "eA==");
    json msg = m is map<json> ? m["message"] : ();
    test:assertTrue(msg is map<json>);
    if msg is map<json> {
        test:assertEquals(msg["subject"], "uat - identity-support-exp-api");
        test:assertEquals(msg["importance"], "High");
        json att = msg["attachments"];
        test:assertEquals(att is json[] && att[0] is map<json> ? (<map<json>>att[0])["@odata.type"] : (), "#microsoft.graph.fileAttachment");
    }
    test:assertEquals(mailImportanceOf("TIMEOUT"), "Low");
    test:assertEquals(mailImportanceOf("BAD_REQUEST"), "Low");
    test:assertEquals(operationNameOf((), "/otp/verify"), "verify");
    test:assertEquals(operationNameOf("Login", "/x"), "Login");
}


@test:Config {}
function producerTargetFollowsMuleChoice() {
    test:assertEquals(producerTargetOf("prod", "ship"), PRODUCER_PROD_SHIP);
    test:assertEquals(producerTargetOf("prod", "shore"), PRODUCER_PROD_SHORE);
    test:assertEquals(producerTargetOf("prod", ""), PRODUCER_PROD_SHORE);
    test:assertEquals(producerTargetOf("uat", "ship"), PRODUCER_UAT);
    test:assertEquals(producerTargetOf("uat", "shore"), PRODUCER_UAT);
    test:assertEquals(producerTargetOf("dev", "shore"), PRODUCER_UAT);
    test:assertEquals(producerTargetOf("", ""), PRODUCER_UAT);
}

@test:Config {}
function emptyPayloadIsNotPublished() {
    test:assertTrue(isEmptyPayload(()));
    test:assertTrue(isEmptyPayload(""));
    test:assertTrue(isEmptyPayload({}));
    test:assertTrue(isEmptyPayload([]));
    test:assertFalse(isEmptyPayload({"a": 1}));
    test:assertFalse(isEmptyPayload("x"));
    test:assertFalse(isEmptyPayload(0));
}
