// HTTP-level tests: the service's operations, started by the test run, against the stand-ins in
// standin_test.bal. Expectations are the answers of e2e/trial.json (the old flows' paths).
import ballerina/http;
import ballerina/lang.runtime;
import ballerina/test;

final http:Client svc = check new ("http://localhost:19781/guest-identity-proc-api/v1", {timeout: 60});

type Answer record {|
    int status;
    string body;
|};

function call(string method, string path, json body = (), map<string> headers = {}) returns Answer|error {
    http:Request request = new;
    if body !is () {
        request.setJsonPayload(body);
    }
    foreach [string, string] [name, value] in headers.entries() {
        request.setHeader(name, value);
    }
    http:Response response = check svc->execute(method, path, request);
    string|http:ClientError text = response.getTextPayload();
    return {status: response.statusCode, body: text is string ? text : ""};
}

function has(Answer a, string... parts) {
    foreach string p in parts {
        test:assertTrue(a.body.includes(p), string `answer ${a.status} lacks ${p}: ${a.body.length() > 300 ? a.body.substring(0, 300) : a.body}`);
    }
}

function waitFor(string tag, int count = 1) {
    foreach int i in 0 ..< 40 {
        if countOf(tag) >= count {
            return;
        }
        runtime:sleep(0.1);
    }
}

json GUEST = {firstName: "Trial", lastName: "Guest", phone: "5550000", mobileCountryCode: "900",
    dateOfBirth: "1990-01-02", email: "trial.guest@example.invalid", gender: "F"};

// ------------------------------------------------------------------ one-time codes

@test:Config {}
function generateLoginByEmail() returns error? {
    useScenario("");
    Answer a = check call("POST", "/otp/generate", {identifier: "Guest@Example.invalid ", channel: "email", context: "login",
        requestId: "3f0c1a2b-1111-4222-8333-444455556666"});
    test:assertEquals(a.status, 202);
    has(a, "\"expiresInSeconds\":300", "\"status\":\"ACTIVE\"", "3f0c1a2b-1111-4222-8333-444455556666");
    test:assertEquals(countOf("insert otp row"), 1);
    test:assertEquals(countOf("insert otp row (bad shape)"), 0);
    test:assertTrue(countOf("e-mail") >= 1);
}

@test:Config {dependsOn: [generateLoginByEmail]}
function generateSameRequestIdAgain() returns error? {
    useScenario("");
    Answer a = check call("POST", "/otp/generate", {identifier: "guest@example.invalid", channel: "email", context: "login",
        requestId: "3f0c1a2b-1111-4222-8333-444455556666"});
    test:assertEquals(a.status, 202);
    test:assertEquals(countOf("insert otp row"), 1);
}

@test:Config {}
function generateLoginByPhone() returns error? {
    useScenario("");
    Answer a = check call("POST", "/otp/generate", {identifier: "+900555000000", channel: "phone", context: "login"});
    test:assertEquals(a.status, 202);
    test:assertEquals(countOf("insert otp row"), 1);
}

@test:Config {}
function generateNotRegistered() returns error? {
    useScenario("not registered");
    Answer a = check call("POST", "/otp/generate", {identifier: "nobody@example.invalid", channel: "email", context: "login"});
    test:assertEquals(a.status, 400);
    has(a, "USER_NOT_REGISTERED");
    test:assertEquals(countOf("insert otp row"), 0);
    test:assertEquals(countOf("e-mail"), 0);
}

@test:Config {}
function generateSignupAlreadyRegistered() returns error? {
    useScenario("");
    Answer a = check call("POST", "/otp/generate", {identifier: "guest@example.invalid", channel: "email", context: "signup",
        metadata: {firstName: "Trial"}});
    test:assertEquals(a.status, 400);
    has(a, "ALREADY_REGISTERED");
    test:assertEquals(countOf("insert otp row"), 0);
}

@test:Config {}
function generateSignupNewGuest() returns error? {
    useScenario("not registered");
    Answer a = check call("POST", "/otp/generate", {identifier: "new.guest@example.invalid", channel: "email", context: "signup",
        metadata: {firstName: "New", lastName: "Guest"}});
    test:assertTrue(a.status == 202 || a.status == 200, a.body);
    test:assertEquals(countOf("insert otp row"), 1);
}

@test:Config {}
function generateRefusesBadInput() returns error? {
    useScenario("");
    Answer noBody = check call("POST", "/otp/generate");
    test:assertEquals(noBody.status, 400);
    Answer noId = check call("POST", "/otp/generate", {channel: "email", context: "login"});
    test:assertEquals(noId.status, 400);
    test:assertEquals(countOf("insert otp row"), 0);
    // the old app takes any other context like a plain code request
    Answer otherContext = check call("POST", "/otp/generate", {identifier: "guest@example.invalid", context: "elsewhere"});
    test:assertTrue(otherContext.status < 500, otherContext.body);
}

@test:Config {}
function generateLockedOrRateLimited() returns error? {
    useScenario("locked");
    Answer locked = check call("POST", "/otp/generate", {identifier: "guest@example.invalid", channel: "email", context: "login"});
    test:assertTrue(locked.status >= 400, locked.body);
    test:assertEquals(countOf("insert otp row"), 0);
    useScenario("rate limited");
    Answer limited = check call("POST", "/otp/generate", {identifier: "guest@example.invalid", channel: "email", context: "login"});
    test:assertTrue(limited.status >= 400, limited.body);
    test:assertEquals(countOf("insert otp row"), 0);
}

@test:Config {}
function generateGuestStoreDownSendsErrorMail() returns error? {
    useScenario("db down");
    Answer a = check call("POST", "/otp/generate", {identifier: "guest@example.invalid", channel: "email", context: "login"});
    test:assertTrue(a.status == 500 || a.status == 502 || a.status == 503, a.status.toString());
    test:assertTrue(countOf("guest store (refused)") >= 1);
    test:assertEquals(countOf("insert otp row"), 0);
    waitFor("error e-mail");
    test:assertTrue(countOf("error e-mail") >= 1, "the error e-mail (switched on in the test settings) was not sent");
}

@test:Config {}
function generateMailDownIsAnError() returns error? {
    useScenario("mail down");
    Answer a = check call("POST", "/otp/generate", {identifier: "guest@example.invalid", channel: "email", context: "login"});
    test:assertTrue(a.status >= 500, "a code that was not e-mailed must not answer sent: " + a.status.toString());
}

@test:Config {}
function verifyRightCode() returns error? {
    useScenario("otp ok");
    Answer a = check call("POST", "/otp/verify", {identifier: "guest@example.invalid", channel: "email", context: "login",
        otpCode: OTP_CODE});
    test:assertEquals(a.status, 200);
    has(a, "\"status\":\"VERIFIED\"", "accessToken");
    test:assertEquals(countOf("mark used"), 1);
    waitFor("guest verified");
    test:assertEquals(countOf("guest verified"), 1);
}

@test:Config {}
function verifySignupRightCode() returns error? {
    useScenario("otp ok");
    Answer a = check call("POST", "/otp/verify", {identifier: "guest@example.invalid", channel: "email", context: "signup",
        otpCode: OTP_CODE});
    test:assertEquals(a.status, 200);
    test:assertEquals(countOf("mark used"), 1);
}

@test:Config {}
function verifyWrongCode() returns error? {
    useScenario("otp ok");
    Answer a = check call("POST", "/otp/verify", {identifier: "guest@example.invalid", channel: "email", context: "login",
        otpCode: "111111"});
    test:assertEquals(a.status, 409);
    has(a, "OTP_INVALID", "\"remainingAttempts\":2");
    test:assertEquals(countOf("count wrong code"), 1);
    test:assertEquals(countOf("mark used"), 0);
}

@test:Config {}
function verifyExpiredCode() returns error? {
    useScenario("otp expired");
    Answer a = check call("POST", "/otp/verify", {identifier: "guest@example.invalid", channel: "email", context: "login",
        otpCode: OTP_CODE});
    test:assertEquals(a.status, 410);
    has(a, "OTP_EXPIRED");
    test:assertEquals(countOf("mark expired"), 1);
    test:assertEquals(countOf("mark used"), 0);
}

@test:Config {}
function verifyNoCodeStored() returns error? {
    useScenario("otp missing");
    Answer a = check call("POST", "/otp/verify", {identifier: "guest@example.invalid", channel: "email", context: "login",
        otpCode: OTP_CODE});
    test:assertEquals(a.status, 404);
    has(a, "OTP_NOT_FOUND");
    test:assertEquals(countOf("mark used"), 0);
    test:assertEquals(countOf("guest verified"), 0);
}

@test:Config {}
function verifyRefusesBadInputAndDownStore() returns error? {
    useScenario("");
    Answer noBody = check call("POST", "/otp/verify");
    test:assertEquals(noBody.status, 400);
    Answer noCode = check call("POST", "/otp/verify", {identifier: "guest@example.invalid", context: "login"});
    test:assertEquals(noCode.status, 400);
    useScenario("db down");
    Answer down = check call("POST", "/otp/verify", {identifier: "guest@example.invalid", channel: "email", context: "login",
        otpCode: OTP_CODE});
    test:assertTrue(down.status >= 500, down.status.toString());
}

// ------------------------------------------------------------------ trips and the Seaware sessions

@test:Config {}
function tripsWithCabins() returns error? {
    useScenario("");
    Answer a = check call("POST", "/guest-profiles/1001", {}, {"device_id": "test-device", "source-system": "mobile"});
    test:assertEquals(a.status, 200);
    has(a, "\"cabins\"", "\"number\":\"8012\"", "\"clientId\":\"1001\"", "\"fullName\":\"Trial Guest\"", "\"primarySailor\":true");
    test:assertTrue(countOf("seaware reservations") >= 1);
}

@test:Config {}
function tripsWithManyReservations() returns error? {
    // the stand-in reservations belong to client 1001; wait out the 2 s trips cache of tripsWithCabins
    runtime:sleep(2.2);
    useScenario("many:50");
    Answer a = check call("POST", "/guest-profiles/1001", {});
    test:assertEquals(a.status, 200);
    has(a, "R150");
}

@test:Config {dependsOn: [tripsWithCabins]}
function seawareSessionIsReusedThenRenewedAfterItsAge() returns error? {
    useScenario("");
    _ = check call("POST", "/guest-profiles/1001", {});
    _ = check call("POST", "/guest-profiles/1001", {});
    test:assertEquals(countOf("seaware sign-in"), 0, "a kept session should be reused");
    runtime:sleep(4);
    useScenario("");
    Answer a = check call("POST", "/guest-profiles/1001", {});
    test:assertEquals(a.status, 200);
    test:assertEquals(countOf("seaware sign-in"), 1, "an expired session should be replaced by one sign-in");
}

@test:Config {dependsOn: [seawareSessionIsReusedThenRenewedAfterItsAge]}
function seawareSessionGoneIsRenewedAndSentAgain() returns error? {
    useScenario("", 1);
    Answer a = check call("POST", "/guest-profiles/1005", {});
    test:assertEquals(a.status, 200);
    test:assertEquals(countOf("seaware session gone"), 1);
    test:assertTrue(countOf("seaware sign-in") >= 1);
    test:assertEquals(countOf("seaware reservations"), 1);
}

@test:Config {dependsOn: [seawareSessionGoneIsRenewedAndSentAgain]}
function seawareSessionGoneTwiceIsAnError() returns error? {
    useScenario("", 2);
    Answer a = check call("POST", "/guest-profiles/1006", {});
    test:assertEquals(a.status, 500);
}

@test:Config {dependsOn: [seawareSessionGoneTwiceIsAnError]}
function concurrentTripsShareFewSignIns() returns error? {
    runtime:sleep(4);
    useScenario("");
    future<Answer|error> a = start call("POST", "/guest-profiles/1007", {});
    future<Answer|error> b = start call("POST", "/guest-profiles/1007", {});
    future<Answer|error> c = start call("POST", "/guest-profiles/1007", {});
    future<Answer|error> d = start call("POST", "/guest-profiles/1007", {});
    Answer|error ra = wait a;
    Answer|error rb = wait b;
    Answer|error rc = wait c;
    Answer|error rd = wait d;
    foreach Answer|error r in [ra, rb, rc, rd] {
        test:assertTrue(r is Answer && r.status == 200);
    }
    test:assertTrue(countOf("seaware sign-in") <= 4, "at most one sign-in per kept session");
}

// Ten travellers of one booking at the same time (the booking front end does this): one Seaware
// sign-in for all of them, each guest's own reservations read once.
@test:Config {dependsOn: [concurrentTripsShareFewSignIns]}
function tenGuestsAtOnceShareOneSignIn() returns error? {
    runtime:sleep(4);
    useScenario("");
    future<Answer|error>[] calls = [];
    foreach int i in 1 ... 10 {
        future<Answer|error> f = start call("POST", "/guest-profiles/11" + (i < 10 ? "0" : "") + i.toString(), {});
        calls.push(f);
    }
    foreach future<Answer|error> f in calls {
        Answer|error r = wait f;
        test:assertTrue(r is Answer && r.status == 200);
    }
    test:assertEquals(countOf("seaware sign-in"), 1, "one shared sign-in for ten guests at the same time");
    test:assertEquals(countOf("seaware reservations"), 10, "each guest's own reservations are read");
}

// The same guest asked several times at once: one Seaware read, then kept for tripsCacheSeconds.
@test:Config {dependsOn: [tenGuestsAtOnceShareOneSignIn]}
function oneGuestAskedAtOnceIsReadOnceAndKept() returns error? {
    useScenario("");
    future<Answer|error>[] calls = [];
    foreach int i in 0 ..< 5 {
        future<Answer|error> f = start call("POST", "/guest-profiles/1201", {});
        calls.push(f);
    }
    string first = "";
    foreach future<Answer|error> f in calls {
        Answer|error r = wait f;
        if r is Answer {
            test:assertEquals(r.status, 200);
            if first == "" {
                first = r.body;
            }
            test:assertEquals(r.body, first);
        } else {
            test:assertFail("no answer");
        }
    }
    Answer again = check call("POST", "/guest-profiles/1201", {});
    test:assertEquals(again.body, first);
    test:assertEquals(countOf("seaware reservations"), 1, "five identical requests and one more: one Seaware read");
    // another guest is never answered from this guest's entry
    Answer other = check call("POST", "/guest-profiles/1202", {});
    test:assertEquals(other.status, 200);
    test:assertEquals(countOf("seaware reservations"), 2);
    runtime:sleep(2.2);
    _ = check call("POST", "/guest-profiles/1201", {});
    test:assertEquals(countOf("seaware reservations"), 3, "read again after tripsCacheSeconds");
}

@test:Config {dependsOn: [oneGuestAskedAtOnceIsReadOnceAndKept]}
function tripsErrorsAreNeverKept() returns error? {
    useScenario("seaware error");
    Answer one = check call("POST", "/guest-profiles/1203", {});
    Answer two = check call("POST", "/guest-profiles/1203", {});
    test:assertEquals(one.status, 502);
    test:assertEquals(two.status, 502);
    test:assertEquals(countOf("seaware error"), 2, "a Seaware error is never kept");
    useScenario("");
    Answer ok = check call("POST", "/guest-profiles/1203", {});
    test:assertEquals(ok.status, 200);
}

@test:Config {}
function tripsWhenSeawareFails() returns error? {
    useScenario("seaware error");
    Answer refused = check call("POST", "/guest-profiles/1002", {});
    test:assertEquals(refused.status, 502);
    useScenario("seaware down");
    Answer down = check call("POST", "/guest-profiles/1003", {});
    test:assertTrue(down.status >= 500, down.status.toString());
}

// ------------------------------------------------------------------ profiles

@test:Config {}
function profileListWithPhotos() returns error? {
    useScenario("photos");
    Answer a = check call("POST", "/guest-profiles", {identifier: "guest@example.invalid"});
    test:assertEquals(a.status, 200);
    test:assertTrue(countOf("photo") >= 1);
}

@test:Config {}
function profileListOverTwoCrmPages() returns error? {
    useScenario("crm two pages");
    Answer a = check call("POST", "/guest-profiles?page=1&perPage=5", {identifier: "guest@example.invalid"});
    test:assertEquals(a.status, 200);
    test:assertTrue(countOf("crm search") >= 2);
}

@test:Config {}
function profileListRefusesBadInputAndDownCrm() returns error? {
    useScenario("");
    test:assertEquals((check call("POST", "/guest-profiles", {})).status, 400);
    test:assertEquals((check call("POST", "/guest-profiles?page=0", {identifier: "guest@example.invalid"})).status, 400);
    Answer byCriteria = check call("POST", "/guest-profiles?criteria=(Email:equals:guest@example.invalid)", {});
    test:assertEquals(byCriteria.status, 200);
    useScenario("zoho down");
    Answer down = check call("POST", "/guest-profiles", {identifier: "guest@example.invalid"});
    test:assertTrue(down.status >= 500, down.status.toString());
}

@test:Config {}
function editProfileAsTheOldApp() returns error? {
    useScenario("");
    Answer a = check call("PUT", "/guest-profiles/1001", {firstName: "Trial", lastName: "Guest", email: "trial.guest@example.invalid"});
    test:assertEquals(a.status, 200, a.body);
    has(a, "\"status\":\"Success\"", "\"ClientId\":\"1001\"", "\"zohoId\":\"Z1\"");
    useScenario("seaware error");
    Answer refused = check call("PUT", "/guest-profiles/1001", {firstName: "Trial", lastName: "Guest"});
    test:assertEquals(refused.status, 400, refused.body);
    useScenario("");
    Answer withPicture = check call("PUT", "/guest-profiles/1001", {firstName: "Trial", lastName: "Guest",
        email: "trial.guest@example.invalid", profileImage: "aGVsbG8="});
    test:assertTrue(withPicture.status == 200 || withPicture.status == 400, withPicture.body);
    test:assertEquals(countOf("crm write"), 1);
    test:assertEquals(countOf("photo upload"), 1, "the picture goes to the CRM contact");
    test:assertEquals((check call("PUT", "/guest-profiles/1001", [1, 2])).status, 400);
}

@test:Config {}
function bookingInfoAndLogin() returns error? {
    useScenario("");
    Answer info = check call("GET", "/processGuestBookingInfo?aroyaloyaltyId=L-1&globalGuestId=G-1");
    test:assertEquals(info.status, 200);
    test:assertEquals((check call("GET", "/processGuestBookingInfo?aroyaloyaltyId=L-1")).status, 400);
    Answer login = check call("POST", "/bookingLogin", {globalGuestId: "G-1", deviceId: "test-device", email: "guest@example.invalid"});
    test:assertEquals(login.status, 200);
    test:assertEquals((check call("POST", "/bookingLogin", "text")).status, 400);
}

// ------------------------------------------------------------------ guest identity

@test:Config {}
function identityOneGuest() returns error? {
    useScenario("");
    Answer a = check call("POST", "/processGuestIdentity", [GUEST], {"client_channel": "web"});
    test:assertEquals(a.status, 200);
    test:assertTrue(a.body.startsWith("["), a.body);
    test:assertTrue(countOf("id generation") >= 1 || countOf("crm search") >= 1);
}

@test:Config {}
function identityExistingClientIsUpdated() returns error? {
    useScenario("client exists");
    Answer a = check call("POST", "/processGuestIdentity", [GUEST], {"client_channel": "web"});
    test:assertEquals(a.status, 200);
}

@test:Config {}
function identityFiveGuests() returns error? {
    useScenario("");
    json[] guests = [];
    foreach int i in 0 ..< 5 {
        guests.push({firstName: "Trial" + i.toString(), lastName: "Guest", phone: "555000" + i.toString(),
            mobileCountryCode: "900", dateOfBirth: "1990-01-02", email: "trial" + i.toString() + "@example.invalid", gender: "F"});
    }
    Answer a = check call("POST", "/processGuestIdentity", guests, {"client_channel": "mobile", "client_device_id": "test-device"});
    test:assertEquals(a.status, 200);
}

@test:Config {}
function identityRefusesAndWhenBackendsFail() returns error? {
    useScenario("");
    test:assertEquals((check call("POST", "/processGuestIdentity", {firstName: "x"})).status, 400);
    Answer realTime = check call("POST", "/processGuestIdentity", [GUEST], {"client_channel": "seawareBatch", "client_realTime": "true"});
    test:assertEquals(realTime.status, 200);
    useScenario("ids down");
    Answer ids = check call("POST", "/processGuestIdentity", [GUEST], {"client_channel": "web"});
    test:assertTrue(ids.status == 200 || ids.status >= 500, ids.body);
    useScenario("zoho down");
    Answer crm = check call("POST", "/processGuestIdentity", [GUEST], {"client_channel": "web"});
    test:assertTrue(crm.status == 200 || crm.status >= 500, crm.body);
    useScenario("seaware down");
    Answer sw = check call("POST", "/processGuestIdentity", [GUEST], {"client_channel": "web"});
    test:assertTrue(sw.status == 200 || sw.status >= 500, sw.body);
}

@test:Config {}
function healthAnswers() returns error? {
    http:Client health = check new ("http://localhost:19781");
    http:Response live = check health->get("/health/live");
    test:assertEquals(live.statusCode, 200);
    http:Response ready = check health->get("/health/ready");
    test:assertEquals(ready.statusCode, 200);
}
