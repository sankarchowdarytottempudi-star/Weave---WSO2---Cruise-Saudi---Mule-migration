import ballerina/test;

@test:Config {}
function queryIsReadFromTheBody() {
    test:assertEquals(queryTextOf("{\"query\":\"query Q { cities { key } }\"}".toBytes()), "query Q { cities { key } }");
    test:assertEquals(queryTextOf("not json".toBytes()), "");
    test:assertEquals(queryTextOf("{\"variables\":{}}".toBytes()), "");
}

@test:Config {}
function authorizationIsForwardedOnlyWhenPresent() {
    map<string> withAuth = seawareHeaders("Bearer x", "c-1");
    test:assertEquals(withAuth["Authorization"], "Bearer x");
    test:assertEquals(withAuth["correlationId"], "c-1");
    test:assertFalse(seawareHeaders((), "c-1").hasKey("Authorization"));
}

@test:Config {}
function errorMessageComesFromTheDownstreamBody() {
    test:assertEquals(messageOf({message: "Unauthorized"}, "UNAUTHORIZED"), "Unauthorized");
    test:assertEquals(messageOf((), "TIMEOUT"), "Seaware answered TIMEOUT");
}
