import ballerina/test;
import aroya/integration_commons as commons;

final RecordFacts FACTS = {correlationId: "c-1", operationName: "createReservation", operationType: "mutation",
                           clientIp: "", authorization: "Bearer secret-token-123", targetSystem: "reservation-common-proc-api",
                           endpointUrl: "http://proc.local/v1/integration-tasks", requestPayload: {query: "mutation createReservation {x}"}};

@test:Config
function auditRecordIsTheOldShape() {
    map<json> r = auditRecordOf(FACTS, {data: {ok: true}}, "2026-11-16T00:00:00Z");
    test:assertEquals(r.keys(), ["session_id", "auth_token", "mule_correlation_id", "step_name", "source_api", "target_system",
        "request_method", "endpoint_url", "graphql_operation_name", "request_headers", "request_payload", "response_status_code",
        "response_headers", "response_payload", "status", "replayable", "retry_count", "error_message", "sw_status", "created_at"]);
    test:assertEquals(r["status"], "SUCCESS");
    test:assertEquals(r["sw_status"], true);
    test:assertEquals(r["source_api"], "reservation-mgr-exp-api");
    test:assertEquals(r["target_system"], "reservation-common-proc-api");
    test:assertEquals((<map<json>>r["request_headers"])["clientIp"], "UNKNOWN");
    // the token is never kept in clear
    test:assertFalse(r.toJsonString().includes("secret-token-123"));
    test:assertTrue((<string>r["session_id"]).startsWith("sha256:"));
    test:assertEquals((<map<json>>r["request_headers"])["authorization"], "MASKED");
}

@test:Config
function errorRecordIsTheOldShape() {
    map<json> r = errorRecordOf(FACTS, {statusCode: 502, message: "backend down"}, 500, "t");
    test:assertEquals(r["status"], "FAILED");
    test:assertEquals(r["sw_status"], false);
    test:assertEquals(r["response_status_code"], 502, "statusCode of the body wins, as in Mule");
    test:assertEquals(r["error_message"], "backend down");
    test:assertEquals(r["replayable"], true);
    RecordFacts other = FACTS.clone();
    other.operationName = "getVoyages";
    other.targetSystem = "";
    map<json> plain = errorRecordOf(other, {other: 1}, 503, "t");
    test:assertEquals(plain["response_status_code"], 503);
    test:assertEquals(plain["error_message"], "UNKNOWN ERROR");
    test:assertEquals(plain["replayable"], false);
    test:assertEquals(plain["target_system"], "SEAWARE");
}

@test:Config
function queriesAndEmptyPayloadsAreNotPublished() {
    RecordFacts query = FACTS.clone();
    query.operationType = "Query";
    test:assertTrue(recordSkipped(query, {a: 1}));
    test:assertTrue(recordSkipped(FACTS, {}));
    test:assertFalse(recordSkipped(FACTS, {a: 1}));
}

@test:Config
function schemaQueriesAreRefusedLikeMule() {
    test:assertTrue(isIntrospection("query IntrospectionQuery { __schema { types { name } } }"));
    test:assertTrue(isIntrospection("{ __type(name: \"X\") { name } }"));
    test:assertFalse(isIntrospection("query getVoyages { voyages { id } }"));
    test:assertEquals(introspectionRefusalOf("t"), {timestamp: "t", statusCode: 400, message: "invalid graphql query",
        correlationId: "UNKNOWN", 'error: "GRAPHQL_QUERY", targetError: "invalid graphql query"});
}

@test:Config {}
function producerFollowsEnvAndTarget() {
    test:assertEquals(producerTargetOf("uat", "shore"), PRODUCER_UAT);
    test:assertEquals(producerTargetOf("uat", "ship"), PRODUCER_UAT);
    test:assertEquals(producerTargetOf("dev", "shore"), PRODUCER_UAT);
    test:assertEquals(producerTargetOf("prod", "ship"), PRODUCER_PROD_SHIP);
    test:assertEquals(producerTargetOf("prod", "shore"), PRODUCER_PROD_SHORE);
    test:assertEquals(producerTargetOf("prod", ""), PRODUCER_PROD_SHORE);
}

@test:Config {}
function brokersOfTheChosenConnection() {
    KafkaProducers p = {uat: {bootstrapServers: ["u:1"]}, prodShip: {bootstrapServers: [" s:2 ", ""]},
        prodShore: {bootstrapServers: ["h:3", "h:4"]}};
    test:assertEquals(serversOf(p, PRODUCER_UAT), ["u:1"]);
    test:assertEquals(serversOf(p, PRODUCER_PROD_SHIP), ["s:2"]);
    test:assertEquals(serversOf(p, PRODUCER_PROD_SHORE), ["h:3", "h:4"]);
    test:assertEquals(serversOf({}, PRODUCER_UAT), []);
}

@test:Config {}
function recordSettingsTakeTheChosenBrokers() {
    KafkaProducers p = {uat: {bootstrapServers: ["u:1"]}, prodShore: {bootstrapServers: ["h:3"]}};
    commons:AuditSettings base = {errorTopic: "e", auditTopic: "a"};
    commons:AuditSettings got = recordSettingsOf(base, p, PRODUCER_PROD_SHORE);
    test:assertEquals(got.bootstrapServers, ["h:3"]);
    test:assertEquals(got.errorTopic, "e");
    test:assertFalse(got.errorEnabled);
    // brokers given directly in the record settings win
    test:assertEquals(recordSettingsOf({bootstrapServers: ["x:9"]}, p, PRODUCER_UAT).bootstrapServers, ["x:9"]);
}

@test:Config {}
function recordSettingsFromReadOnlyConfiguration() {
    // configurable values are read-only, as at runtime
    KafkaProducers & readonly p = {uat: {bootstrapServers: ["u:1"]}};
    commons:AuditSettings & readonly base = {errorTopic: "e", errorEnabled: true, maxBlockSeconds: 2};
    commons:AuditSettings got = recordSettingsOf(base, p, PRODUCER_UAT);
    test:assertEquals(got.bootstrapServers, ["u:1"]);
    test:assertTrue(got.errorEnabled);
    test:assertEquals(got.maxBlockSeconds, 2d);
}
