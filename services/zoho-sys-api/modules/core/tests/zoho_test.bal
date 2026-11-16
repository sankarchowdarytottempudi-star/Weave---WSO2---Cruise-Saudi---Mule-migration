import ballerina/test;

final ZohoAccount & readonly ACCOUNT = {clientId: "1000.ABC", clientSecret: "s3cr3t/+=", refreshToken: "1000.r&t"};

@test:Config {}
function headerWinsOverAddress() {
    test:assertEquals(zohoPathOf("/crm/v2/Contacts/search", ["Leads", "77"]), "/crm/v2/Contacts/search");
    test:assertEquals(zohoPathOf("crm/v3/settings/modules", []), "/crm/v3/settings/modules");
    test:assertEquals(zohoPathOf("   ", ["Leads"]), "/crm/v2/Leads");
}

@test:Config {}
function addressGivesModuleAndRecord() {
    test:assertEquals(zohoPathOf((), ["Leads"]), "/crm/v2/Leads");
    test:assertEquals(zohoPathOf((), ["Leads", "4150868000000624001"]), "/crm/v2/Leads/4150868000000624001");
    // Mule used the module and one record id only
    test:assertEquals(zohoPathOf((), ["Leads", "77", "Notes", "9"]), "/crm/v2/Leads/77");
    test:assertEquals(zohoPathOf((), ["My Module", "a/b"]), "/crm/v2/My%20Module/a%2Fb");
    test:assertEquals(zohoPathOf((), ["Leads"], "/crm/v6"), "/crm/v6/Leads");
    test:assertEquals(zohoPathOf((), []), "");
    test:assertEquals(zohoPathOf((), [""]), "");
}

@test:Config {}
function unsafePathsAreRefused() {
    test:assertTrue(isSafePath("/crm/v2/Leads/77?x=1"));
    test:assertFalse(isSafePath("//other.example.test/x"));
    test:assertFalse(isSafePath("crm/v2/Leads"));
    test:assertFalse(isSafePath("/crm/v2/Le ads"));
    test:assertFalse(isSafePath("/crm/v2/Leads\\x"));
    test:assertFalse(isSafePath("/crm/v2/Leads\n"));
}

@test:Config {}
function photoPathIsRecognised() {
    test:assertTrue(isPhotoPath("/crm/v2/Contacts/77/photo"));
    test:assertTrue(isPhotoPath("/crm/v2/Contacts/77/photo?x=1"));
    test:assertFalse(isPhotoPath("/crm/v2/Contacts/77/photos"));
    test:assertFalse(isPhotoPath("/crm/v2/photography"));
}

@test:Config {}
function tokenRequestIsFormEncoded() {
    test:assertEquals(tokenFormOf(ACCOUNT),
            "grant_type=refresh_token&client_id=1000.ABC&client_secret=s3cr3t%2F%2B%3D&refresh_token=1000.r%26t");
}

@test:Config {}
function accountSettingsAreChecked() {
    test:assertEquals(missingAccountSetting(ACCOUNT), ());
    test:assertEquals(missingAccountSetting({}), "zohoAccount.clientId");
    test:assertEquals(missingAccountSetting({clientId: "a", clientSecret: " "}), "zohoAccount.clientSecret");
    test:assertEquals(missingAccountSetting({clientId: "a", clientSecret: "b"}), "zohoAccount.refreshToken");
}

@test:Config {}
function accessTokenIsRead() {
    test:assertEquals(accessTokenOf({access_token: " tok-1 ", expires_in: 3600}), "tok-1");
    string|error refused = accessTokenOf({'error: "invalid_client"});
    test:assertTrue(refused is error);
    if refused is error {
        test:assertEquals(refused.message(), "Zoho did not issue an access token (invalid_client)");
    }
    // a reason that is not a plain code is never repeated to the caller
    string|error odd = accessTokenOf({'error: "see https://accounts.example.test/x"});
    if odd is error {
        test:assertEquals(odd.message(), "Zoho did not issue an access token");
    } else {
        test:assertFail("expected an error");
    }
    test:assertTrue(accessTokenOf(()) is error);
    test:assertTrue(accessTokenOf("text") is error);
    test:assertEquals(authorizationOf("tok-1"), "Zoho-oauthtoken tok-1");
}

@test:Config {}
function cachedTokenRules() {
    test:assertTrue(tokenUsable("tok-1", 1000, 999));
    test:assertFalse(tokenUsable("tok-1", 1000, 1000));
    test:assertFalse(tokenUsable("", 1000, 1));
    test:assertFalse(tokenUsable("tok-1", 1000, 1, "tok-1"));
    test:assertTrue(tokenUsable("tok-2", 1000, 1, "tok-1"));
}

@test:Config {}
function expiredTokenAnswerIsRecognised() {
    test:assertTrue(isExpiredTokenAnswer({code: "INVALID_TOKEN", details: {}, message: "invalid oauth token", status: "error"}));
    test:assertTrue(isExpiredTokenAnswer({message: "Invalid OAuth Token"}));
    test:assertTrue(isExpiredTokenAnswer({code: "INVALID_TOKEN"}));
    test:assertFalse(isExpiredTokenAnswer({code: "INVALID_MODULE", message: "the module name given seems to be invalid"}));
    test:assertFalse(isExpiredTokenAnswer("invalid oauth token"));
    test:assertFalse(isExpiredTokenAnswer(()));
}

@test:Config {}
function answersAreRead() {
    test:assertEquals(answerOf("{\"data\":[{\"id\":\"1\"}]}".toBytes()), {data: [{id: "1"}]});
    test:assertEquals(answerOf("not json".toBytes()), "not json");
    test:assertEquals(answerOf([]), ());
    test:assertEquals(errorMessageOf({message: "the module name given seems to be invalid"}, 400),
            "the module name given seems to be invalid");
    test:assertEquals(errorMessageOf("oops", 502), "Zoho answered 502");
    test:assertEquals(errorMessageOf((), 500), "Zoho answered 500");
}

@test:Config {}
function errorTypesFollowTheStatus() {
    test:assertEquals(errorTypeOfStatus(400), "BAD_REQUEST");
    test:assertEquals(errorTypeOfStatus(401), "UNAUTHORIZED");
    test:assertEquals(errorTypeOfStatus(403), "FORBIDDEN");
    test:assertEquals(errorTypeOfStatus(404), "NOT_FOUND");
    test:assertEquals(errorTypeOfStatus(429), "TOO_MANY_REQUESTS");
    test:assertEquals(errorTypeOfStatus(500), "INTERNAL_SERVER_ERROR");
    test:assertEquals(errorTypeOfStatus(504), "GATEWAY_TIMEOUT");
    test:assertEquals(errorTypeOfStatus(418), "CLIENT_ERROR");
}

@test:Config {}
function photoIsDecoded() returns error? {
    byte[] bytes = check photoBytesOf({file: "aGVsbG8="});
    test:assertEquals(bytes, "hello".toBytes());
    test:assertTrue(photoBytesOf({file: "###"}) is error);
    test:assertTrue(photoBytesOf({}) is error);
    test:assertTrue(photoBytesOf({file: ""}) is error);
    test:assertTrue(photoBytesOf([1]) is error);
}

@test:Config {}
function queryIsCarriedOver() {
    test:assertEquals(withQuery("/crm/v2/Leads", {}), "/crm/v2/Leads");
    test:assertEquals(withQuery("/crm/v2/Leads", {"per_page": ["1"]}), "/crm/v2/Leads?per_page=1");
    test:assertEquals(withQuery("/crm/v2/Leads/search?a=1", {"criteria": ["(Email:equals:a@b.test)"]}),
            "/crm/v2/Leads/search?a=1&criteria=%28Email%3Aequals%3Aa%40b.test%29");
    test:assertTrue(isPlaceholderAddress("http://localhost"));
    test:assertTrue(isPlaceholderAddress(""));
    test:assertFalse(isPlaceholderAddress("https://crm.example.test"));
}
