import ballerina/test;

@test:Config {}
function otpGenerateHeadersUseSourceSystemFirst() {
    map<string> headers = otpGenerateHeaders("dev-1", "10.0.0.1", "mobile", "web");
    test:assertEquals(headers, {"device_id": "dev-1", "client-ip": "10.0.0.1", "source-system": "mobile", "client_channel": "mobile"});
}

@test:Config {}
function otpGenerateHeadersFallBackToClientChannel() {
    test:assertEquals(otpGenerateHeaders((), (), (), "web"), {"source-system": "web", "client_channel": "web"});
    test:assertEquals(otpGenerateHeaders((), (), (), ()), {});
}

@test:Config {}
function onlyPresentValuesArePassedOn() {
    test:assertEquals(presentHeaders({"client_channel": "web", "client_realTime": (), "client_device_id": "d"}),
            {"client_channel": "web", "client_device_id": "d"});
    test:assertEquals(presentQuery({"site": "web", "locale": ()}), {"site": ["web"]});
}

@test:Config {}
function errorMappingRequestNamesEndpointAndCode() {
    map<json> request = errorMappingRequestOf("/otp/verify", 409);
    test:assertEquals(request["connectionKey"], "PG_Guest");
    test:assertEquals(request["params"], {"endpoint": "/otp/verify", "code": "409"});
    test:assertEquals(errorMappingRequestOf("", 500)["params"], {"endpoint": "UNKNOWN", "code": "500"});
}

@test:Config {}
function mappedRowWinsOverTheBackendAnswer() {
    json original = {"code": "OTP_INVALID"};
    test:assertEquals(mappedErrorOf([{"error": "Invalid code", "type": "BUSINESS", "code": "409"}], original),
            {"error": "Invalid code", "type": "BUSINESS", "code": "409"});
    test:assertEquals(mappedErrorOf([], original), original);
    test:assertEquals(mappedErrorOf((), original), original);
}

@test:Config {}
function fallbackAndPlainErrors() {
    test:assertEquals(fallbackErrorOf("a", "b"), {"messageType": "UNKNOWN", "message": "An unexpected error occurred",
        "responseCode": 500, "source": "a", "target": "b", "errorDoesNotExist": true});
    test:assertEquals(plainErrorOf("CONNECTIVITY", "no answer", ()), {"messageType": "CONNECTIVITY", "message": "no answer",
        "responseCode": (), "responsePayload": (), "errorDoesNotExist": false});
}

@test:Config {}
function commonHelpers() {
    test:assertTrue(isPlaceholderAddress("http://localhost"));
    test:assertTrue(isPlaceholderAddress(""));
    test:assertFalse(isPlaceholderAddress("http://guest-identity-proc-api.wso2.svc"));
    test:assertEquals(withQuery("/a", {"site": ["web app"], "locale": ["en"]}), "/a?site=web%20app&locale=en");
    test:assertEquals(pathSegment("C 1/2"), "C%201%2F2");
}


@test:Config {}
function aMappedRowIsAnsweredWhenTheMappingIsReadable() {
    json rows = [{"error": "OTP is not valid", "type": "VALIDATION", "code": "400"}, {"error": "second"}];
    test:assertEquals(mappedBodyOf(rows), {"error": "OTP is not valid", "type": "VALIDATION", "code": "400"});
}

@test:Config {}
function theProcessApisOwnErrorIsAnsweredWhenNothingIsMapped() {
    json none = [];
    test:assertEquals(mappedBodyOf(none), ());
    json notRows = {"message": "no rows"};
    test:assertEquals(mappedBodyOf(notRows), ());
}

@test:Config {}
function theProcessApisOwnErrorIsAnsweredWhenTheMappingCannotBeRead() {
    // the database system API answered 503, or did not answer: no 500 in place of the real error
    test:assertEquals(mappedBodyOf(error("The database system API answered 503")), ());
}
