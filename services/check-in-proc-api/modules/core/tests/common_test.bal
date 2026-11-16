import ballerina/test;

@test:Config {}
function placeholderAddressesAreRecognised() {
    test:assertTrue(isPlaceholderAddress(""));
    test:assertTrue(isPlaceholderAddress("http://localhost"));
    test:assertTrue(isPlaceholderAddress("HTTP://LOCALHOST:9090"));
    test:assertTrue(isPlaceholderAddress("http://127.0.0.1:8080"));
    test:assertFalse(isPlaceholderAddress("http://otalio-sys-api-new.wso2.svc.cluster.local"));
}

@test:Config {}
function withQueryKeepsTheQueryOfThePath() {
    test:assertEquals(withQuery("/integration-tasks?operationName=getLinkedPerson",
            [["operationName", "getLinkedPerson"], ["shipId", "S 1"]]),
            "/integration-tasks?operationName=getLinkedPerson&operationName=getLinkedPerson&shipId=S%201");
    test:assertEquals(withQuery("/integration-tasks", [["operationName", "uploadDocuments"]]),
            "/integration-tasks?operationName=uploadDocuments");
    test:assertEquals(withQuery("/files", []), "/files");
    test:assertEquals(withQuery("/x", [["httpMethod", ""], ["a&b", "c=d"]]), "/x?httpMethod=&a%26b=c%3Dd");
}

@test:Config {}
function baseMediaTypeDropsParameters() {
    test:assertEquals(baseMediaTypeOf("multipart/form-data; boundary=abc"), "multipart/form-data");
    test:assertEquals(baseMediaTypeOf("Application/JSON"), "application/json");
    test:assertEquals(baseMediaTypeOf(""), "");
}

@test:Config {}
function emptyValuesAreMulesIsEmpty() {
    test:assertTrue(isEmptyValue(()));
    test:assertTrue(isEmptyValue(""));
    test:assertTrue(isEmptyValue("  "));
    test:assertTrue(isEmptyValue({}));
    test:assertTrue(isEmptyValue([]));
    test:assertFalse(isEmptyValue({"a": 1}));
    test:assertFalse(isEmptyValue([1]));
    test:assertFalse(isEmptyValue("x"));
    test:assertFalse(isEmptyValue(0));
    test:assertFalse(isEmptyValue(false));
}
