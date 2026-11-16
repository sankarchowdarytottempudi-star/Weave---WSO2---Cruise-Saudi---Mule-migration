import ballerina/test;

@test:Config {}
function cmsErrorMailAsMule() {
    json m = errorMailOf("cms-proc-api", "CONNECTIVITY", "d", "x", "to@example.invalid", "cc@example.invalid", false);
    test:assertTrue(m is map<json>);
    if m is map<json> {
        json msg = m["message"];
        test:assertEquals(msg is map<json> ? msg["subject"] : (), "⚠️cms-proc-api");
        test:assertEquals(m["saveToSentItems"], false);
        test:assertFalse(m.toJsonString().includes("attachments"));
    }
    json low = errorMailOf("cms-proc-api", "NOT_FOUND", "d", "x", "t", "c", true);
    test:assertTrue(low.toJsonString().includes("\"subject\":\"cms-proc-api\""));
}
