import ballerina/test;

@test:Config {}
function eventsFolioKeepsOrderAndLeavesOutMissing() {
    Call c = eventsFolioCall("2", (), "10", "name");
    test:assertEquals(c.method, "GET");
    test:assertEquals(c.query, [["operationName", "getEventsFolio"], ["page", "2"], ["size", "10"], ["sort", "name"]]);
    test:assertEquals(c.headers, {"Content-Type": "application/json"});
    test:assertEquals(c.body, NO_BODY);
}

@test:Config {}
function searchOnlyOperations() {
    test:assertEquals(amenityCall("pool").query, [["operationName", "getamenity"], ["search", "pool"]]);
    test:assertEquals(amenityCodesCall(()).query, [["operationName", "getamenity-codes"]]);
    test:assertEquals(packagesCall("spa").query, [["operationName", "getPackages"], ["search", "spa"]]);
    test:assertEquals(packagesCall("spa").operation, "getPackages");
}

@test:Config {}
function personSearchPassesEveryParameter() {
    [string, string][] params = pairsOf({"search": ["a"], "tag": ["x", "y"]});
    test:assertEquals(personSearchCall(params).query,
            [["operationName", "getPersonSearch"], ["search", "a"], ["tag", "x"], ["tag", "y"]]);
    test:assertEquals(personByReservationCall("R1", [["page", "1"]]).query,
            [["operationName", "getPersonByReservationID"], ["shipId", "R1"], ["page", "1"]]);
    test:assertEquals(reservationByIdCall("R2", []).query, [["operationName", "getReservationByID"], ["shipId", "R2"]]);
}

@test:Config {}
function postCallsCarryClientName() {
    Call m = messagesCall(());
    test:assertEquals(m.method, "POST");
    test:assertEquals(m.body, CALLER_BODY);
    test:assertEquals(m.headers["client_name"], "MuleSoft");
    test:assertEquals(messageStatusesCall("mobile").headers["client_name"], "mobile");
    test:assertEquals(messageStatusesCall(()).query, [["operationName", "statusmessage"]]);
    test:assertEquals(bulkUpdateCall(()).query, [["operationName", "bulkUpdateReservations"], ["httpMethod", "PATCH"]]);
    test:assertEquals(bulkUpdateCall(()).method, "POST");
}

@test:Config {}
function routerAnswers() {
    test:assertEquals(routerAnswerOf(["getamenity"]), [405, {"message": "Method not allowed"}]);
    test:assertEquals(routerAnswerOf(["reservation", "v1", "person-search", "7"]), [405, {"message": "Method not allowed"}]);
    test:assertEquals(routerAnswerOf(["nothing"]), [404, {"message": "Resource not found"}]);
}

@test:Config {}
function integerParameters() {
    test:assertTrue(isIntegerOrAbsent(()));
    test:assertTrue(isIntegerOrAbsent("12"));
    test:assertFalse(isIntegerOrAbsent("abc"));
    test:assertFalse(isIntegerOrAbsent(""));
}

@test:Config {}
function bodyChecks() {
    test:assertEquals(bodyRefusalOf("application/json", "[1]".toBytes(), "array"), ());
    test:assertEquals(bodyRefusalOf("application/json; charset=utf-8", "[]".toBytes(), "array"), ());
    test:assertEquals(bodyRefusalOf("application/json", "{}".toBytes(), "array"), [400, {"message": "Bad request"}]);
    test:assertEquals(bodyRefusalOf("application/json", [], "array"), [400, {"message": "Bad request"}]);
    test:assertEquals(bodyRefusalOf("application/json", "nope".toBytes(), "array"), [400, {"message": "Bad request"}]);
    test:assertEquals(bodyRefusalOf("text/plain", "[1]".toBytes(), "array"), [415, {"message": "Unsupported media type"}]);
    test:assertEquals(bodyRefusalOf("", [], "object"), ());
    test:assertEquals(bodyRefusalOf("application/json", "{\"a\":1}".toBytes(), "object"), ());
    test:assertEquals(bodyRefusalOf("application/json", "[1]".toBytes(), "object"), [400, {"message": "Bad request"}]);
}

@test:Config {}
function errorHelpers() {
    test:assertTrue(isSuccess(204));
    test:assertFalse(isSuccess(302));
    test:assertEquals(errorStatusOf(()), 500);
    test:assertEquals(errorStatusOf(404), 404);
    test:assertTrue(shouldRetry("TIMEOUT", ["HTTP:TIMEOUT"], 1));
    test:assertFalse(shouldRetry("TIMEOUT", ["HTTP:TIMEOUT"], 0));
    test:assertFalse(shouldRetry("NOT_FOUND", ["CONNECTIVITY"], 3));
    test:assertEquals(customErrorOf("CONNECTIVITY", "m", ()),
            {"messageType": "CONNECTIVITY", "message": "m", "responseCode": (), "responsePayload": (), "errorDoesNotExist": false});
}

@test:Config {}
function recordsAndCommon() {
    test:assertEquals(bodyRecordOf("application/json", "[1]".toBytes()), [1]);
    test:assertEquals(bodyRecordOf("text/plain", "hi".toBytes()), "hi");
    test:assertEquals(bodyRecordOf("application/octet-stream", [1, 2]), {"contentType": "application/octet-stream", "bytes": 2});
    test:assertEquals(bodyRecordOf("", []), ());
    test:assertFalse(isPublishable((), {"a": 1}));
    test:assertFalse(isPublishable([], {"a": 1}));
    test:assertTrue(isPublishable([1], {"a": 1}));
    test:assertTrue(isPlaceholderAddress("http://localhost"));
    test:assertFalse(isPlaceholderAddress("https://otalio.example.test"));
    test:assertEquals(withQuery("/p", [["a", "1 2"], ["b", "x&y"]]), "/p?a=1%202&b=x%26y");
    test:assertEquals(withQuery("/p?z=1", [["a", "b"]]), "/p?z=1&a=b");
    test:assertEquals(baseMediaTypeOf("Application/JSON; charset=utf-8"), "application/json");
    test:assertTrue(isEmptyValue(""));
    test:assertFalse(isEmptyValue(0));
}
