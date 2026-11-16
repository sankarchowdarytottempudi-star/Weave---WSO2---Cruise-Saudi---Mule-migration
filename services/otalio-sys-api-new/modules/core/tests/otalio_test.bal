import ballerina/test;

final map<string> & readonly PATHS = {
    "getArticles": "/pos/v1/pos-operations/get-all-checks",
    "getFolio": "/finance/v1/posting-detail/folio/{ID}",
    "checkImage": "/pos/v1/pos-operations/{ID}/check-image",
    "postTransactions": "/pos/v1/pos-operations/external-fast-transactions",
    "deleteCustomValue": "/pms/v1/custom-attribute-values/{ID}",
    "guestprofile": "pms/v1/person-profiles",
    "twice": "/a/{ID}/b/{ID}"
};

@test:Config {}
function operationGivesItsPath() returns error? {
    test:assertEquals(check targetPathOf(PATHS, "getArticles", ""), "/pos/v1/pos-operations/get-all-checks");
    test:assertEquals(check targetPathOf(PATHS, "getFolio", "ACC77"), "/finance/v1/posting-detail/folio/ACC77");
    test:assertEquals(check targetPathOf(PATHS, "checkImage", "CHK9"), "/pos/v1/pos-operations/CHK9/check-image");
    // Mule: no shipId -> the id is empty
    test:assertEquals(check targetPathOf(PATHS, "getFolio", ""), "/finance/v1/posting-detail/folio/");
    test:assertEquals(check targetPathOf(PATHS, "guestprofile", ""), "/pms/v1/person-profiles");
    test:assertEquals(check targetPathOf(PATHS, "twice", "7"), "/a/7/b/7");
    // an id can never leave its place in the path
    test:assertEquals(check targetPathOf(PATHS, "getFolio", "../x?y"), "/finance/v1/posting-detail/folio/..%2Fx%3Fy");
}

@test:Config {}
function unknownOperationIsRefused() {
    string|error unknown = targetPathOf(PATHS, "noSuch<script>", "");
    if unknown is error {
        test:assertEquals(unknown.message(), "Unknown operationName: noSuchscript");
    } else {
        test:assertFail("expected an error");
    }
    test:assertTrue(targetPathOf({}, "getArticles", "") is error);
}

@test:Config {}
function queryIsPassedOnWithoutOwnParameters() {
    map<string[]> query = {"operationName": ["getArticles"], "httpMethod": ["PUT"], "shipId": ["S1"], "from": ["2026-01-01 00:00"]};
    test:assertEquals(without(query, ["operationName"]), {"httpMethod": ["PUT"], "shipId": ["S1"], "from": ["2026-01-01 00:00"]});
    test:assertEquals(without(query, ["operationName", "httpMethod"]), {"shipId": ["S1"], "from": ["2026-01-01 00:00"]});
    test:assertEquals(firstOf(query, "operationName"), "getArticles");
    test:assertEquals(firstOf(query, "missing"), ());
    test:assertEquals(firstOf({"operationName": [" "]}, "operationName"), ());
    test:assertEquals(withQuery("/pos/v1/x", without(query, ["operationName", "httpMethod"])),
            "/pos/v1/x?shipId=S1&from=2026-01-01%2000%3A00");
}

@test:Config {}
function methodsFollowTheMuleRules() returns error? {
    test:assertEquals(readMethodOf("getArticles"), "GET");
    test:assertEquals(readMethodOf("deleteCustomValue"), "DELETE");
    test:assertEquals(check writeMethodOf(()), "POST");
    test:assertEquals(check writeMethodOf(""), "POST");
    test:assertEquals(check writeMethodOf("PATCH"), "PATCH");
    test:assertEquals(check writeMethodOf("put"), "PUT");
    string|error refused = writeMethodOf("DELETE");
    if refused is error {
        test:assertEquals(refused.message(), "Unsupported HTTP Method: DELETE");
    } else {
        test:assertFail("expected an error");
    }
}

@test:Config {}
function headersPassedOn() {
    test:assertTrue(isForwardedHeader("client_channel"));
    test:assertTrue(isForwardedHeader("correlationId"));
    test:assertTrue(isForwardedHeader("Accept"));
    test:assertFalse(isForwardedHeader("Authorization"));
    test:assertFalse(isForwardedHeader("Host"));
    test:assertFalse(isForwardedHeader("Content-Length"));
    test:assertFalse(isForwardedHeader("content-type"));
    test:assertFalse(isForwardedHeader("X-JWT-Assertion"));
    test:assertFalse(isForwardedHeader("Proxy-Authorization"));
}

@test:Config {}
function signInBodiesAndAnswers() {
    test:assertEquals(loginBodyOf({login: " svc ", password: "p w"}), {password: "p w", login: "svc"});
    test:assertEquals(refreshBodyOf("r-1"), {refreshToken: "r-1"});
    json login = {responsePayload: {refresh_token: "r-1", access_token: "a-1", expires_in: 600}};
    test:assertEquals(refreshTokenOf(login), "r-1");
    test:assertEquals(accessTokenOf(login), "a-1");
    test:assertEquals(accessTokenOf({responsePayload: {}}), ());
    test:assertEquals(accessTokenOf({access_token: "top-level"}), ());
    test:assertEquals(refreshTokenOf("text"), ());
    test:assertEquals(bearerOf("a-1"), "Bearer a-1");
    test:assertEquals(missingAccountSetting({login: "svc", password: "p"}), ());
    test:assertEquals(missingAccountSetting({}), "otalioAccount.login");
    test:assertEquals(missingAccountSetting({login: "svc"}), "otalioAccount.password");
}

@test:Config {}
function accessTokenLifetime() {
    test:assertEquals(accessLifetimeOf({responsePayload: {access_token: "a", expires_in: 600}}, 300), 300);
    test:assertEquals(accessLifetimeOf({responsePayload: {access_token: "a", expires_in: 120}}, 300), 90);
    test:assertEquals(accessLifetimeOf({responsePayload: {access_token: "a", expires_in: 20}}, 300), 0);
    test:assertEquals(accessLifetimeOf({responsePayload: {access_token: "a"}}, 300), 300);
    test:assertEquals(accessLifetimeOf({responsePayload: {access_token: "a", expires_in: 600}}, 0), 0);
}

@test:Config {}
function rememberedSignIn() {
    TokenState state = {refreshToken: "r-1", refreshExpiresAt: 2000, authorization: "Bearer a-1", authorizationExpiresAt: 1000};
    test:assertTrue(authorizationUsable(state, 999));
    test:assertFalse(authorizationUsable(state, 1000));
    test:assertFalse(authorizationUsable(state, 1, "Bearer a-1"));
    test:assertFalse(authorizationUsable({}, 1));
    test:assertTrue(refreshUsable(state, 1999));
    test:assertFalse(refreshUsable(state, 2000));
    test:assertFalse(refreshUsable({}, 1));
}

@test:Config {}
function callerPathsAreChecked() {
    test:assertTrue(isSafePath("/core/v1/metadata?x=1"));
    test:assertFalse(isSafePath("//other.example.test/x"));
    test:assertFalse(isSafePath("core/v1"));
    test:assertFalse(isSafePath("/core/v1 x"));
    test:assertTrue(isPlaceholderAddress("http://localhost"));
    test:assertFalse(isPlaceholderAddress("https://otalio.example.test"));
}
