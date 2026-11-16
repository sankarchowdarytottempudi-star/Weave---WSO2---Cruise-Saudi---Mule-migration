import ballerina/test;

@test:Config {}
function onlyTwoHundredsAreSuccess() {
    test:assertTrue(isSuccess(200));
    test:assertTrue(isSuccess(201));
    test:assertTrue(isSuccess(299));
    test:assertFalse(isSuccess(199));
    test:assertFalse(isSuccess(304));
    test:assertFalse(isSuccess(400));
    test:assertFalse(isSuccess(502));
}

@test:Config {}
function successStatusIsTheBackendsOnlyWhereMuleSetIt() {
    test:assertEquals(answerStatusOf(true, 201), 201);
    test:assertEquals(answerStatusOf(true, 204), 204);
    test:assertEquals(answerStatusOf(false, 201), 200);
    test:assertEquals(answerStatusOf(false, 200), 200);
}

@test:Config {}
function errorStatusDefaultsToFiveHundred() {
    test:assertEquals(errorStatusOf(404), 404);
    test:assertEquals(errorStatusOf(502), 502);
    test:assertEquals(errorStatusOf(()), 500);
}

@test:Config {}
function retryNeedsRepeatsLeftAndAListedType() {
    string[] types = ["HTTP:BAD_GATEWAY", "HTTP:CONNECTIVITY", "HTTP:TIMEOUT"];
    test:assertFalse(shouldRetry("CONNECTIVITY", types, 0));
    test:assertTrue(shouldRetry("CONNECTIVITY", types, 1));
    test:assertTrue(shouldRetry("TIMEOUT", types, 2));
    test:assertTrue(shouldRetry("BAD_GATEWAY", ["bad_gateway"], 1));
    test:assertFalse(shouldRetry("BAD_REQUEST", types, 3));
    test:assertFalse(shouldRetry("NOT_FOUND", types, 3));
    test:assertFalse(shouldRetry("CONNECTIVITY", [], 3));
    test:assertFalse(shouldRetry("CONNECTIVITY", types, -1));
}

@test:Config {}
function customErrorHasMulesFields() {
    test:assertEquals(customErrorOf("NOT_FOUND", "nothing there", 404), {
        "messageType": "NOT_FOUND",
        "message": "nothing there",
        "responseCode": 404,
        "responsePayload": (),
        "errorDoesNotExist": false
    });
    map<json> unreachable = customErrorOf("CONNECTIVITY", "could not be reached", ());
    test:assertEquals(unreachable["responseCode"], ());
    test:assertEquals(unreachable["errorDoesNotExist"], false);
    test:assertEquals(unreachable.keys(), ["messageType", "message", "responseCode", "responsePayload", "errorDoesNotExist"]);
}

@test:Config {}
function routerAnswersLikeTheMuleRouter() {
    test:assertEquals(routerAnswerOf(["travelDocuments"]), [405, {"message": "Method not allowed"}]);
    test:assertEquals(routerAnswerOf(["travel-documents", "12"]), [405, {"message": "Method not allowed"}]);
    test:assertEquals(routerAnswerOf(["travel-documents", "12", "file"]), [405, {"message": "Method not allowed"}]);
    test:assertEquals(routerAnswerOf(["paymentToken"]), [405, {"message": "Method not allowed"}]);
    test:assertEquals(routerAnswerOf(["updateEmergencyContact"]), [405, {"message": "Method not allowed"}]);
    test:assertEquals(routerAnswerOf(["getLinkedPerson"]), [405, {"message": "Method not allowed"}]);
    test:assertEquals(routerAnswerOf(["uploadDocuments"]), [405, {"message": "Method not allowed"}]);
    test:assertEquals(routerAnswerOf(["nothing"]), [404, {"message": "Resource not found"}]);
    test:assertEquals(routerAnswerOf(["travel-documents", "12", "other"]), [404, {"message": "Resource not found"}]);
    test:assertEquals(routerAnswerOf(["travel-documents"]), [404, {"message": "Resource not found"}]);
    test:assertEquals(routerAnswerOf([]), [404, {"message": "Resource not found"}]);
}

@test:Config {}
function bodyRecordKeepsJsonAndText() {
    test:assertEquals(bodyRecordOf("application/json", "{\"a\":1}".toBytes()), {"a": 1});
    test:assertEquals(bodyRecordOf("application/json; charset=UTF-8", "[1,2]".toBytes()), [1, 2]);
    test:assertEquals(bodyRecordOf("", "{\"a\":1}".toBytes()), {"a": 1});
    test:assertEquals(bodyRecordOf("text/plain", "not json".toBytes()), "not json");
    test:assertEquals(bodyRecordOf("application/json", "broken {".toBytes()), "broken {");
    test:assertEquals(bodyRecordOf("application/json", []), ());
}

@test:Config {}
function bodyRecordNeverCopiesBinaryContent() {
    test:assertEquals(bodyRecordOf("image/png", [1, 2, 3]), {"contentType": "image/png", "bytes": 3});
    test:assertEquals(uploadRecordOf("multipart/form-data; boundary=x", 2),
            {"contentType": "multipart/form-data", "parts": 2});
}

@test:Config {}
function errorRecordIsSkippedForEmptyRequestOrError() {
    test:assertTrue(isPublishable({"a": 1}, {"message": "failed"}));
    test:assertTrue(isPublishable({"contentType": "multipart/form-data", "parts": 1}, "failed"));
    test:assertFalse(isPublishable((), {"message": "failed"}));
    test:assertFalse(isPublishable({}, {"message": "failed"}));
    test:assertFalse(isPublishable({"a": 1}, ()));
    test:assertFalse(isPublishable({"a": 1}, ""));
}
