import ballerina/test;
import ballerina/time;

function utc(string text) returns time:Utc {
    time:Utc|time:Error moment = time:utcFromString(text);
    if moment is time:Error {
        panic moment;
    }
    return moment;
}

@test:Config {}
function generateRequestIsNormalized() {
    map<json> request = generateRequestOf({"identifier": " Ann@Example.com ", "channel": "email", "context": " SignUp ",
                "metadata": {"firstName": "Ann"}}, "dev1", (), "web");
    test:assertEquals(request["identifier"], "ann@example.com");
    test:assertEquals(request["context"], "signup");
    test:assertEquals(request["deviceId"], "dev1");
    test:assertEquals(request["ipAddress"], ());
    test:assertEquals(request["sourceChannel"], "web");
    test:assertEquals(generateRequestOf({"identifier": " +966A ", "channel": "sms"}, (), (), "x")["identifier"], "+966A");
    test:assertEquals(verifyRequestOf({"identifier": " Ann@Example.com", "otpCode": " 123456 "})["identifier"], "ann@example.com");
    test:assertEquals(verifyRequestOf({"identifier": "a", "otpCode": " 123456 "})["otpCode"], "123456");
}

@test:Config {}
function passwordsHaveSixDigits() {
    test:assertEquals(otpCodeOf("00000000-0000-4000-8000-000000000000"), "100000");
    test:assertEquals(otpCodeOf("00000000-0000-4000-8000-00000000000f"), "100015");
    test:assertEquals(otpCodeOf("00000000-0000-4000-8000-0000000dbba0"), "100000");
    test:assertEquals(otpCodeOf("ffffffff-ffff-4fff-bfff-ffffffffffff").length(), 6);
    test:assertEquals(otpCodeOf("not a uuid").length(), 6);
}

@test:Config {}
function passwordHash() {
    test:assertEquals(otpHashOf("123456", "salt"), "5NL5SaQBwE6c0L1BDjHW+BtBOXQVH8RYwY0tGGw3khk=");
    map<json> row = {"salt": "salt", "otp_hash": "5NL5SaQBwE6c0L1BDjHW+BtBOXQVH8RYwY0tGGw3khk="};
    test:assertTrue(otpMatches(row, "123456"));
    test:assertFalse(otpMatches(row, "123457"));
    test:assertFalse(otpMatches({"otp_hash": "5NL5SaQBwE6c0L1BDjHW+BtBOXQVH8RYwY0tGGw3khk="}, "123456"));
}

@test:Config {}
function maskedIdentifiers() {
    test:assertEquals(maskedForMail("john.doe@example.com"), "joh***@example.com");
    test:assertEquals(maskedForMail("ab@x.com"), "***@x.com");
    test:assertEquals(maskedForMail("966500001234"), "966******234");
    test:assertEquals(maskedForAnswer("john.doe@example.com"), "joh***@exam");
    test:assertEquals(maskedForAnswer("a@b.c"), "a@b.c");
}

@test:Config {}
function locks() {
    test:assertEquals(retryAfterOf([{"retry_after": 61}]), 61);
    test:assertEquals(retryAfterOf([{"retry_after": "90"}]), 90);
    test:assertEquals(retryAfterOf([]), 0);
    test:assertEquals(lockedAnswerOf(61), {
        "code": "OTP_LOCKED",
        "message": "Too many failed attempts. Try again in 2 minutes.",
        "retryAfterSeconds": 61
    });
    test:assertTrue(rateLimited([{"cnt": 6}]));
    test:assertTrue(rateLimited([{"cnt": "9"}]));
    test:assertFalse(rateLimited([{"cnt": 5}]));
    test:assertFalse(rateLimited([]));
}

@test:Config {}
function requestIds() {
    test:assertEquals(safeRequestId("123e4567-e89b-42d3-a456-426614174000", "fresh"), "123e4567-e89b-42d3-a456-426614174000");
    test:assertEquals(safeRequestId("abc", "fresh"), "fresh");
    test:assertEquals(safeRequestId((), "fresh"), "fresh");
}

@test:Config {}
function moments() {
    time:Utc ten = utc("2026-11-15T10:00:00Z");
    test:assertEquals(stampOf(utc("2026-11-15T10:05:09Z")), "2026-11-15 10:05:09");
    test:assertEquals(momentOf("2026-11-15 10:00:00"), ten);
    test:assertEquals(momentOf("2026-11-15T10:00:00+00"), ten);
    test:assertEquals(momentOf("2026-11-15T13:00:00+03:00"), ten);
    test:assertEquals(momentOf("2026-11-15T10:00:00Z"), ten);
    test:assertEquals(momentOf(""), ());
    test:assertEquals(momentOf("soon"), ());
}

@test:Config {}
function storedPasswordRequest() {
    map<json> request = generateRequestOf({"identifier": "ann@example.com", "channel": "email", "context": "login"}, (), (), "web");
    map<json> insert = otpInsertOf(request, "rid", "hash", "salt", utc("2026-11-15T10:05:00Z"), ());
    test:assertEquals(insert["operation"], "insert");
    test:assertEquals(fieldOf(insert, "params", "expiresAt"), "2026-11-15 10:05:00+00");
    test:assertEquals(fieldOf(insert, "params", "metadata"), "{}");
    test:assertEquals(fieldOf(insert, "params", "requestId"), "rid");
    test:assertEquals(fieldOf(insert, "params", "gid"), ());
    test:assertFalse(textOf(insert["query"]).includes("ann@example.com"));
}

@test:Config {}
function passwordLookup() {
    test:assertTrue(textOf(otpLookupOf({"requestId": "r1"})["query"]).includes("request_id = :requestId"));
    map<json> byIdentifier = otpLookupOf({"identifier": "a@b.co", "channel": "email", "context": "login"});
    test:assertTrue(textOf(byIdentifier["query"]).includes("ORDER BY created_at DESC LIMIT 1"));
    test:assertEquals(fieldOf(byIdentifier, "params", "identifier"), "a@b.co");
}

@test:Config {}
function storedPasswordStates() {
    time:Utc now = utc("2026-11-15T10:00:00Z");
    test:assertEquals(otpCheckOf((), now, 30).outcome, "notFound");
    test:assertEquals(otpCheckOf((), now, 30).status, 404);
    OtpCheck used = otpCheckOf({"status": "USED"}, now, 30);
    test:assertEquals([used.outcome, used.status], ["used", 400]);
    OtpCheck locked = otpCheckOf({"status": "LOCKED"}, now, 30);
    test:assertEquals([locked.outcome, locked.status], ["locked", 429]);
    test:assertEquals(locked.body["message"], "Too many failed attempts. Try again after 30 minutes.");
    test:assertEquals(otpCheckOf({"status": "ACTIVE", "attempts": 3}, now, 30).outcome, "locked");
    OtpCheck expired = otpCheckOf({"status": "ACTIVE", "attempts": 0, "max_attempts": 3,
                "expires_at": "2026-11-15T09:59:59Z"}, now, 30);
    test:assertEquals([expired.outcome, expired.status], ["expired", 410]);
    test:assertEquals(otpCheckOf({"status": "ACTIVE", "attempts": 0}, now, 30).outcome, "expired");
    test:assertEquals(otpCheckOf({"status": "ACTIVE", "attempts": 2, "max_attempts": 3,
                "expires_at": "2026-11-15 10:04:00"}, now, 30).outcome, "compare");
}

@test:Config {}
function wrongPasswordAnswers() {
    [int, map<json>] [status, body] = wrongCodeAnswerOf({"status": "ACTIVE", "attempts": 1, "max_attempts": 3}, 30);
    test:assertEquals(status, 409);
    test:assertEquals(body, {"code": "OTP_INVALID", "message": "Invalid OTP code", "remainingAttempts": 2});
    [int, map<json>] [lockedStatus, lockedBody] = wrongCodeAnswerOf({"status": "LOCKED", "attempts": 3}, 30);
    test:assertEquals(lockedStatus, 429);
    test:assertEquals(lockedBody["retryAfterSeconds"], 1800);
    [int, map<json>] [_, unknown] = wrongCodeAnswerOf((), 30);
    test:assertEquals(unknown["remainingAttempts"], 0);
}

@test:Config {}
function attemptRequests() {
    map<json> row = {"otp_id": "o1"};
    test:assertEquals(fieldOf(markUsedOf(row), "params", "otpId"), "o1");
    test:assertTrue(textOf(markExpiredOf(row)["query"]).includes("SET status = 'EXPIRED'"));
    test:assertEquals(fieldOf(failedAttemptOf(row, 30), "params", "lockMinutes"), 30);
    test:assertEquals(attemptStateOf(row)["operation"], "select");
    test:assertTrue(textOf(guestVerifiedOf(row)["query"]).includes("status = 'verified'"));
}

@test:Config {}
function accessToken() {
    string|error token = accessTokenOf("ann@example.com", "unit-test-key", 1000);
    string|error again = accessTokenOf("ann@example.com", "unit-test-key", 1000);
    string|error otherKey = accessTokenOf("ann@example.com", "another-key", 1000);
    if token is error || again is error || otherKey is error {
        test:assertFail("token not signed");
    }
    string[] parts = re `\.`.split(token);
    test:assertEquals(parts.length(), 3);
    test:assertEquals(parts[0], "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9");
    test:assertFalse(token.includes("=") || token.includes("+") || token.includes("/"));
    test:assertEquals(token, again);
    test:assertEquals(re `\.`.split(otherKey)[1], parts[1]);
    test:assertNotEquals(re `\.`.split(otherKey)[2], parts[2]);
}

@test:Config {}
function verifiedAnswers() {
    map<json> login = verifiedAnswerOf("login", "tok", "ref");
    test:assertEquals(fieldOf(login, "session", "accessToken"), "tok");
    test:assertEquals(fieldOf(login, "session", "expiresIn"), 3600);
    test:assertEquals(verifiedAnswerOf("signup")["message"], "Account verified successfully.");
    test:assertFalse(verifiedAnswerOf("signup").hasKey("session"));
}

@test:Config {}
function signupGuest() {
    map<json> guest = signupGuestOf({"firstName": "Ann", "gender": "Female", "phone": "500"}, "ann@example.com");
    test:assertEquals(guest["firstName"], "Ann");
    test:assertEquals(guest["gender"], "F");
    test:assertEquals(guest["email"], "ann@example.com");
    test:assertEquals(guest["phone"], "500");
    test:assertEquals(signupGuestOf((), "a@b.co")["gender"], ());
    test:assertEquals(loginCriteriaOf((), "a@b.co"), "((Email:equals:a@b.co))");
    test:assertEquals(loginCriteriaOf("(X:equals:1)", "a@b.co"), "(X:equals:1)");
}

@test:Config {}
function passwordMail() {
    map<json> mail = otpEmailOf("john.doe@example.com", "654321", utc("2026-11-15T10:05:00Z"), "http://logo.test/l.png");
    string body = textOf(mail["body"]);
    test:assertEquals(mail["to"], <json>["john.doe@example.com"]);
    test:assertTrue(body.includes("654321"));
    test:assertTrue(body.includes("joh***@example.com"));
    test:assertFalse(body.includes("john.doe@"));
    test:assertTrue(body.includes("Expires: 2026-11-15 10:05:00"));
    map<json> answer = generateAnswerOf("r1", "john.doe@example.com");
    test:assertEquals(answer, {"requestId": "r1", "expiresInSeconds": 300, "maskedIdentifier": "joh***@exam", "status": "ACTIVE"});
}

@test:Config {}
function welcomeMail() {
    map<json> plain = welcomeEmailOf("ann@example.com", (), (), "http://logo.test/l.png", "http://app.test/");
    test:assertEquals(plain["subject"], "Welcome Aboard");
    test:assertTrue(textOf(plain["body"]).includes("http://app.test/"));
    json cms = {"data": [{"page_title": "Hello", "components": [{"title": "Ahoy", "description": "Dear {{name}}",
                        "cta": [{"text": "Go", "link_url": "http://cta.test/"}]}]}]};
    map<json> rich = welcomeEmailOf("ann@example.com", "{\"firstName\":\"<Ann>\"}", cms, "", "");
    string body = textOf(rich["body"]);
    test:assertEquals(rich["subject"], "Hello");
    test:assertTrue(body.includes("Dear &lt;Ann&gt;"));
    test:assertTrue(body.includes("http://cta.test/"));
}

// The old application raises these by name; its error handler answers 400 with messageType.
@test:Config {}
function raisedErrorsAnswerLikeTheOldHandler() {
    test:assertEquals(RAISED_STATUS, 400);
    test:assertEquals(notRegistered().toJsonString(),
            "{\"messageType\":\"USER_NOT_REGISTERED\", \"message\":\"Please register before login\", "
            + "\"responseCode\":400, \"responsePayload\":null, \"errorDoesNotExist\":false}");
    test:assertEquals(alreadyRegistered(), {
        "messageType": "ALREADY_REGISTERED",
        "message": "Account already exists. Please login.",
        "responseCode": 400,
        "responsePayload": (),
        "errorDoesNotExist": false
    });
    test:assertEquals(rateLimitAnswer(), {"code": "RATE_LIMIT", "message": "Too many OTP requests. Please try again later."});
}
