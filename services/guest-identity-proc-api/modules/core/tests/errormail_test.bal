import ballerina/test;

@test:Config {}
function errorMailAsMule() {
    json m = errorMailOf("uat", "guest-identity-proc-api", "INTERNAL_SERVER_ERROR", "d", "{}", "to@example.invalid",
            "cc@example.invalid", "e30=");
    json msg = m is map<json> ? m["message"] : ();
    test:assertTrue(msg is map<json>);
    if msg is map<json> {
        test:assertEquals(msg["subject"], "uat - guest-identity-proc-api");
        test:assertEquals(msg["importance"], "High");
        test:assertTrue(msg["toRecipients"].toJsonString().includes("to@example.invalid"));
        test:assertTrue(msg["attachments"].toJsonString().includes("contentBytes"));
    }
    test:assertEquals(errorTypeOfStatus(503), "SERVICE_UNAVAILABLE");
    test:assertEquals(mailImportanceOf("NOT_FOUND"), "Low");
}
