import ballerina/test;

// A copy of a read-only sample that a test may change.
function copyOf(map<json> sample) returns map<json> {
    map<json> copy = {};
    foreach [string, json] [name, value] in sample.entries() {
        copy[name] = value;
    }
    return copy;
}

@test:Config {}
function capitalizeWords() {
    test:assertEquals(capitalize("saudi arabia"), "Saudi Arabia");
    test:assertEquals(capitalize("UNITED_STATES"), "United States");
    test:assertEquals(capitalize("camelCase"), "Camel Case");
    test:assertEquals(capitalize(""), "");
}

@test:Config {}
function emailAddresses() {
    test:assertTrue(emailValid("ann.lee+1@example.co"));
    test:assertFalse(emailValid("ann@example"));
    test:assertFalse(emailValid("ann lee@example.com"));
    test:assertFalse(emailValid(()));
    test:assertFalse(emailValid(12));
}

@test:Config {}
function nullSafeReading() {
    json value = {"a": {"b": [1, 2]}, "n": "7", "d": 2.9};
    test:assertEquals(fieldOf(value, "a", "b"), <json>[1, 2]);
    test:assertEquals(fieldOf(value, "a", "x", "y"), ());
    test:assertEquals(fieldOf("text", "a"), ());
    test:assertEquals(listOf(fieldOf(value, "a")).length(), 1);
    test:assertEquals(listOf("x").length(), 0);
    test:assertEquals(intOf(fieldOf(value, "n"), 1), 7);
    test:assertEquals(intOf(fieldOf(value, "d"), 1), 2);
    test:assertEquals(intOf("many", 10), 10);
    test:assertEquals(textOf(()), "");
    test:assertEquals(trimmed("  a "), "a");
    test:assertFalse(has([]));
    test:assertFalse(has(""));
    test:assertTrue(has(0));
}

@test:Config {}
function textMadeSafe() {
    test:assertEquals(sqlText("O'Neil"), "'O''Neil'");
    test:assertEquals(bareWord("M } drop"), "Mdrop");
    test:assertEquals(gqlText("a\"b\\c"), "a\\\"b\\\\c");
    test:assertEquals(htmlText("<b>&"), "&lt;b&gt;&amp;");
}

@test:Config {}
function queryParameters() {
    test:assertEquals(withQuery("/a", {"page": ["2"]}), "/a?page=2");
    test:assertEquals(withQuery("/a?x=1", {"y": ["b"]}), "/a?x=1&y=b");
    test:assertTrue(!withQuery("/a", {"criteria": ["(Email:equals:a b@c.d)"]}).includes(" "));
}

@test:Config {}
function placeholderAddresses() {
    test:assertTrue(isPlaceholderAddress("http://localhost"));
    test:assertTrue(isPlaceholderAddress(""));
    test:assertFalse(isPlaceholderAddress("http://zoho-sys-api.wso2.svc"));
}

@test:Config {}
function databaseRequests() {
    test:assertEquals(dbRequestOf("select", "SELECT 1"),
            {"connectionKey": "PG_Guest", "operation": "select", "query": "SELECT 1"});
    test:assertEquals(dbRequestOf("insert", "X", {"a": 1})["params"], <json>{"a": 1});
    test:assertEquals(firstRowOf([{"id": 4}]), <map<json>>{"id": 4});
    test:assertEquals(firstRowOf({"id": 4}), ());
    test:assertEquals(rowsOf("x").length(), 0);
}

@test:Config {}
function seawareSessions() {
    test:assertEquals(loginTokenOf({"data": {"login": {"token": "T1"}}}), "T1");
    test:assertEquals(loginTokenOf({"data": {"login": ()}}), ());
    test:assertEquals(bearerOf("T1"), "Bearer T1");
    test:assertEquals(bearerOf("Bearer T1"), "Bearer T1");
    test:assertEquals(firstSeawareError({"errors": [{"message": "No such client"}]}), "No such client");
    test:assertEquals(firstSeawareError({"data": {}}), ());
    test:assertTrue(isSessionError("Session context not found or expired"));
    test:assertFalse(isSessionError("No such client"));
    string login = textOf(loginRequestOf({userName: "agent\"x", password: "p"})["query"]);
    test:assertTrue(login.includes("login: \"agent\\\"x\""));
}

@test:Config {}
function fieldsInsideVariablesAreRead() {
    json wrapped = {"variables": {"identifier": " A@B.example ", "channel": "email", "context": "Login", "metadata": {"isGuest": true}}};
    map<json>? fields = requestFieldsOf(wrapped);
    test:assertTrue(fields is map<json>);
    if fields is map<json> {
        test:assertEquals(trimmed(fields["identifier"]), "A@B.example");
        map<json> normal = generateRequestOf(fields, (), (), "unknown");
        test:assertEquals(normal["identifier"], "a@b.example");
        test:assertEquals(normal["context"], "login");
        test:assertEquals(normal["metadata"], {"isGuest": true});
    }
}

@test:Config {}
function fieldsAtTheTopStayAsTheyAre() {
    json plain = {"identifier": "a@b.example", "otpCode": "123456", "variables": {"identifier": "other@b.example"}};
    map<json>? fields = requestFieldsOf(plain);
    test:assertEquals(fields, <map<json>>plain);
    // a "variables" that is not an object is not a wrapper
    json odd = {"variables": "x", "channel": "email"};
    test:assertEquals(requestFieldsOf(odd), <map<json>>odd);
}

@test:Config {}
function aBodyThatIsNotAnObjectHasNoFields() {
    test:assertEquals(requestFieldsOf(()), ());
    test:assertEquals(requestFieldsOf("text"), ());
    test:assertEquals(requestFieldsOf([{"identifier": "a@b.example"}]), ());
}

@test:Config {}
function onlyTheTwoHundredRangeMeansHandedOver() {
    test:assertTrue(handedOver(200));
    test:assertTrue(handedOver(202));
    test:assertFalse(handedOver(308));
    test:assertFalse(handedOver(302));
    test:assertFalse(handedOver(199));
    test:assertFalse(handedOver(400));
}
