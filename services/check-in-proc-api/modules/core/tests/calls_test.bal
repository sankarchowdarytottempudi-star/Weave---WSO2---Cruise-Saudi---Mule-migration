import ballerina/test;

@test:Config {}
function linkedPersonIsAReadWithTheShipId() {
    Call call = linkedPersonCall("S1");
    test:assertEquals(call.method, "GET");
    test:assertEquals(call.pathKey, "getLinkedPerson");
    test:assertEquals(call.query, [["operationName", "getLinkedPerson"], ["shipId", "S1"]]);
    test:assertEquals(call.headers, {"Content-Type": "application/json"});
    test:assertEquals(call.body, NO_BODY);
    test:assertFalse(call.backendStatus);
}

@test:Config {}
function linkedPersonWithoutIdSendsNoShipId() {
    test:assertEquals(linkedPersonCall(()).query, [["operationName", "getLinkedPerson"]]);
}

@test:Config {}
function emergencyContactIsAPostThatNamesPut() {
    Call call = emergencyContactCall("S2");
    test:assertEquals(call.method, "POST");
    test:assertEquals(call.pathKey, "updateEmergencyContact");
    test:assertEquals(call.query,
            [["operationName", "updateEmergencyContact"], ["httpMethod", "PUT"], ["shipId", "S2"]]);
    test:assertEquals(call.headers, {});
    test:assertEquals(call.body, CALLER_BODY);
    test:assertFalse(call.backendStatus);
}

@test:Config {}
function emergencyContactWithoutIdSendsNoShipId() {
    test:assertEquals(emergencyContactCall(()).query,
            [["operationName", "updateEmergencyContact"], ["httpMethod", "PUT"]]);
}

@test:Config {}
function fileUploadIsADocumentOnlyWhenAskedFor() {
    Call document = fileUploadCall("77", "uploadFile");
    test:assertEquals(document.method, "POST");
    test:assertEquals(document.pathKey, "uploadFile");
    test:assertEquals(document.query, [["shipId", "77"]]);
    test:assertEquals(document.body, UPLOAD);
    test:assertTrue(document.backendStatus);
    test:assertEquals(fileUploadCall("77", ()).pathKey, "personPicture");
    test:assertEquals(fileUploadCall("77", "somethingElse").pathKey, "personPicture");
}

@test:Config {}
function documentCallChoosesThePathByOperationName() {
    Call plain = documentCall("9", ());
    test:assertEquals(plain.method, "GET");
    test:assertEquals(plain.pathKey, "getDocumentsId");
    test:assertEquals(plain.query, [["shipId", "9"]]);
    test:assertEquals(plain.headers, {"Content-Type": "application/json"});
    test:assertFalse(plain.backendStatus);
    test:assertEquals(documentCall("9", "showPersonPicture").pathKey, "showPersonPicture");
    test:assertEquals(documentCall("9", "deleteCustomValue").pathKey, "deleteCustomValue");
    test:assertEquals(documentCall("9", "other").pathKey, "getDocumentsId");
}

@test:Config {}
function allDocumentsSendsNoQuery() {
    Call call = allDocumentsCall();
    test:assertEquals(call.method, "GET");
    test:assertEquals(call.pathKey, "getAllDocuments");
    test:assertEquals(call.query, []);
    test:assertEquals(call.headers, {"Content-Type": "application/json"});
    test:assertEquals(call.body, NO_BODY);
}

@test:Config {}
function uploadDocumentsForCustomAttributes() {
    Call call = uploadDocumentsCall("customAttributesCheckIn", "PATCH", "5");
    test:assertEquals(call.method, "POST");
    test:assertEquals(call.pathKey, "customAttributesCheckIn");
    test:assertEquals(call.query, [["operationName", "customAttributesCheckIn"]]);
    test:assertEquals(call.body, JSON_BODY);
    test:assertTrue(call.backendStatus);
}

@test:Config {}
function uploadDocumentsWithAnotherOperationPassesMethodAndId() {
    Call call = uploadDocumentsCall("updatePersonProfile", "PATCH", "5");
    test:assertEquals(call.pathKey, "uploadDocuments");
    test:assertEquals(call.query, [["httpMethod", "PATCH"], ["shipId", "5"], ["operationName", "updatePersonProfile"]]);
    test:assertTrue(call.backendStatus);
    // Mule: `default ""` for the ones the caller did not send
    test:assertEquals(uploadDocumentsCall("x", (), ()).query, [["httpMethod", ""], ["shipId", ""], ["operationName", "x"]]);
    test:assertEquals(uploadDocumentsCall("", (), ()).query, [["httpMethod", ""], ["shipId", ""], ["operationName", ""]]);
}

@test:Config {}
function uploadDocumentsWithoutOperationNameIsUploadDocuments() {
    Call call = uploadDocumentsCall((), "PUT", "5");
    test:assertEquals(call.pathKey, "uploadDocuments");
    test:assertEquals(call.query, [["operationName", "uploadDocuments"]]);
    test:assertEquals(call.body, JSON_BODY);
    test:assertTrue(call.backendStatus);
}

@test:Config {}
function paymentTokenPassesTheAuthorizationOn() {
    Call call = paymentTokenCall("Bearer test-token");
    test:assertEquals(call.method, "POST");
    test:assertEquals(call.pathKey, "paymentToken");
    test:assertEquals(call.query, []);
    test:assertEquals(call.headers, {"Authorization": "Bearer test-token"});
    test:assertEquals(call.body, JSON_BODY);
    test:assertTrue(call.backendStatus);
    test:assertEquals(paymentTokenCall(()).headers, {});
}

@test:Config {}
function everyCallHasABuiltInPath() {
    string[] keys = [
        linkedPersonCall(()).pathKey, emergencyContactCall(()).pathKey, fileUploadCall("1", "uploadFile").pathKey,
        fileUploadCall("1", ()).pathKey, documentCall("1", ()).pathKey, documentCall("1", "showPersonPicture").pathKey,
        documentCall("1", "deleteCustomValue").pathKey, allDocumentsCall().pathKey,
        uploadDocumentsCall("customAttributesCheckIn", (), ()).pathKey, uploadDocumentsCall((), (), ()).pathKey,
        paymentTokenCall(()).pathKey
    ];
    foreach string key in keys {
        test:assertTrue(pathOf("/otalio-sys-api-new/v1", {}, key) is string, key);
    }
    test:assertEquals(DEFAULT_PATHS.length(), 11);
}

@test:Config {}
function pathOfJoinsBaseAndPath() {
    test:assertEquals(pathOf("/otalio-sys-api-new/v1", {}, "getLinkedPerson"),
            "/otalio-sys-api-new/v1/integration-tasks?operationName=getLinkedPerson");
    test:assertEquals(pathOf("/base/", {}, "uploadDocuments"), "/base/integration-tasks");
    test:assertEquals(pathOf("", {}, "uploadFile"), "/files?operationName=uploadFile");
    test:assertEquals(pathOf("/base", {}, "paymentToken"), "/base/integration-tasks?operationName=paymentAuthorization");
}

@test:Config {}
function pathOfUsesTheSettingFirst() {
    test:assertEquals(pathOf("/base", {"getLinkedPerson": "/other?x=1"}, "getLinkedPerson"), "/base/other?x=1");
    test:assertEquals(pathOf("/base", {"getLinkedPerson": "other"}, "getLinkedPerson"), "/base/other");
    test:assertEquals(pathOf("/base", {"showPersonPicture": ""}, "showPersonPicture"), ());
    test:assertEquals(pathOf("/base", {}, "unknown"), ());
}
