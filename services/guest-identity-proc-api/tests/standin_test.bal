// Stand-in backends for the service tests: the replies of e2e/standin.py, as a Ballerina test
// listener. Every backend address in tests/Config.toml is http://127.0.0.2:19771/_b/<setting name>.
// Made-up data only. A test sets the scenario; every call is recorded as a tag.
import ballerina/crypto;
import ballerina/http;
import ballerina/lang.runtime;

const int STANDIN_PORT = 19771;
const string OTP_CODE = "246810";
const string SALT = "trial-salt";

isolated string scenario = "";
isolated string[] tags = [];
isolated int sessionErrorsLeft = 0;
// seconds the stand-in Seaware takes for a reservations query (a slow lookup)
isolated decimal seawareDelay = 0;

// reservations queries running at the same time, per session token, and the most seen
type QueryCount record {|
    map<int> running;
    int most;
|};

isolated QueryCount queryCount = {running: {}, most: 0};

isolated function enterQuery(string token) {
    lock {
        int now = (queryCount.running[token] ?: 0) + 1;
        queryCount.running[token] = now;
        if now > queryCount.most {
            queryCount.most = now;
        }
    }
}

isolated function leaveQuery(string token) {
    lock {
        queryCount.running[token] = (queryCount.running[token] ?: 1) - 1;
    }
}

isolated function mostConcurrentQueries() returns int {
    lock {
        return queryCount.most;
    }
}

isolated function resetConcurrency() {
    lock {
        queryCount.most = 0;
    }
}

isolated function setSeawareDelay(decimal seconds) {
    lock {
        seawareDelay = seconds;
    }
}

isolated function useScenario(string name, int sessionErrors = 0) {
    lock {
        scenario = name;
    }
    lock {
        tags = [];
    }
    lock {
        sessionErrorsLeft = sessionErrors;
    }    lock {
        seawareDelay = 0;
    }
}

isolated function scenarioNow() returns string {
    lock {
        return scenario;
    }
}

isolated function noteCall(string tag) {
    lock {
        tags.push(tag);
    }
}

isolated function tagsSeen() returns string[] {
    lock {
        return tags.clone();
    }
}

isolated function countOf(string tag) returns int {
    lock {
        return tags.filter(t => t == tag).length();
    }
}

isolated function takeSessionError() returns boolean {
    lock {
        if sessionErrorsLeft > 0 {
            sessionErrorsLeft -= 1;
            return true;
        }
        return false;
    }
}

isolated function otpHash() returns string => crypto:hashSha256((OTP_CODE + SALT).toBytes()).toBase64();

isolated function otpRow(boolean expired) returns json => {
    otp_id: "00000000-0000-4000-8000-000000000001",
    identifier: "guest@example.invalid",
    channel: "email",
    context: "login",
    otp_hash: otpHash(),
    salt: SALT,
    attempts: 0,
    max_attempts: 3,
    status: "ACTIVE",
    expires_at: expired ? "2001-01-01 00:00:00+00" : "2099-01-01 00:00:00+00",
    created_at: "2026-01-01 00:00:00+00",
    request_id: (),
    cs_guest_core_id: "core-1"
};

isolated function reservationEdge(int i) returns json {
    json guest = {
        seqN: 1,
        age: 40,
        'client: {key: 1001, fullName: "Trial Guest", firstName: "Trial", lastName: "Guest", eMail: "guest@example.invalid",
            mobileIntlCode: "900", mobilePhoneNumber: "5550000"},
        voyages: [
            {
                pkg: {key: "PKG1", name: "Red Sea", 'type: {name: "Cruise", comments: "4 nights", key: "C"},
                    destinations: [{name: "Sea", comments: "Sea"}]},
                sail: {'from: {dateTime: "2099-04-01T16:00:00", port: {key: "AAA", name: "Port A"}},
                    to: {dateTime: "2099-04-05T08:00:00", port: {key: "BBB", name: "Port B"}}},
                cabinChain: [{cabin: {number: "8012", category: {comments: "Suite", code: "S1"}, deck: {number: 8}}}]
            }
        ]
    };
    string key = "R" + (101 + i).toString();
    return {
        node: {
            key: key,
            id: "Reservation|" + key,
            sourceCode: "WEB",
            version: 1,
            guestCount: 1,
            initialDate: "2026-01-01T09:00:00",
            lastUpdated: "2026-01-03T11:00:00",
            currency: {key: "SAR"},
            status: {name: "Booked", key: "BK"},
            invoiceTotals: {invoiceTotal: 1000, currentDue: {amount: 100, date: "2099-03-01", 'type: "D"}, payments: 0,
                pendingPayments: 0, pendingRefunds: 0},
            contact: {key: 1001, fullName: "Trial Guest", eMail: "guest@example.invalid"},
            guests: [guest],
            language: {key: "EN"},
            group: (),
            agency: ()
        },
        cursor: "c" + i.toString()
    };
}

isolated function reservations(int count) returns json {
    json[] edges = [];
    foreach int i in 0 ..< count {
        edges.push(reservationEdge(i));
    }
    return {data: {reservations: {edges, pageInfo: {hasPreviousPage: false, hasNextPage: false, count, totalCount: count}}}};
}

isolated function dbReply(string sc, string q, json body) returns [int, json, string] {
    if sc == "db down" {
        return [503, {message: "stand-in: guest store down"}, "guest store (refused)"];
    }
    if q.includes("retry_after") {
        return [200, [{retry_after: sc == "locked" ? 600 : 0}], "lock check"];
    }
    if q.startsWith("SELECT otp_id, identifier, channel") {
        if sc == "not registered" {
            return [200, [], "registered check (none)"];
        }
        return [200, [{otp_id: "o-0", identifier: "guest@example.invalid", channel: "email", metadata: {}}], "registered check"];
    }
    if q.includes("count(*) AS cnt") {
        return [200, [{cnt: sc == "rate limited" ? 99 : 0}], "rate limit"];
    }
    if q.includes("FROM cs_guest_mgmt.cs_guest_core WHERE global_guest_id") {
        return [200, [{id: "core-1"}], "guest lookup"];
    }
    if q.startsWith("INSERT INTO cs_guest_mgmt.cs_otp_store") {
        json params = body is map<json> ? body["params"] : ();
        boolean ok = params is map<json> && params["otpHash"] is string && params["salt"] is string
            && params["expiresAt"].toString().endsWith("+00");
        return [200, {status: "ok"}, ok ? "insert otp row" : "insert otp row (bad shape)"];
    }
    if q.startsWith("SELECT * FROM cs_guest_mgmt.cs_otp_store") {
        if sc == "otp missing" {
            return [200, [], "otp lookup (none)"];
        }
        return [200, [otpRow(sc == "otp expired")], "otp lookup"];
    }
    if q.includes("SET status = 'EXPIRED'") {
        return [200, {status: "ok"}, "mark expired"];
    }
    if q.includes("SET status = 'USED'") {
        return [200, {status: "ok"}, "mark used"];
    }
    if q.includes("status = 'verified'") {
        return [200, {status: "ok"}, "guest verified"];
    }
    if q.includes("attempts = attempts + 1") {
        return [200, {status: "ok"}, "count wrong code"];
    }
    if q.startsWith("SELECT attempts, max_attempts") {
        return [200, [{attempts: 1, max_attempts: 3, status: "ACTIVE"}], "attempts"];
    }
    return [200, {status: "ok"}, "other statement"];
}

isolated function zohoReply(string sc, string method, string zohoPath) returns [int, json, string] {
    if sc == "zoho down" {
        return [503, {message: "stand-in: CRM down"}, "crm (refused)"];
    }
    if zohoPath.endsWith("/photo") {
        if method == "GET" {
            return sc == "photos" ? [200, {photo: "aGVsbG8="}, "photo"] : [204, (), "photo"];
        }
        return [200, {data: [{code: "SUCCESS", status: "success"}]}, "photo upload"];
    }
    if method == "GET" {
        if sc == "not registered" {
            return [204, (), "crm search (none)"];
        }
        boolean more = sc == "crm two pages" && !zohoPath.includes("page=2");
        return [200, {data: [{id: "Z1", Email: "guest@example.invalid", Client_ID: "1001", First_Name: "Trial",
                    Last_Name: "Guest", Modified_Time: "2026-01-01T10:00:00+03:00"}], info: {more_records: more}}, "crm search"];
    }
    return [200, {data: [{code: "SUCCESS", status: "success", details: {id: "Z1"}}]}, "crm write"];
}

isolated function seawareReply(string sc, string q) returns [int, json, string] {
    if sc == "seaware down" {
        return [503, {message: "stand-in: Seaware down"}, "seaware (refused)"];
    }
    if q.includes("reservations(") {
        decimal delay;
        lock {
            delay = seawareDelay;
        }
        if delay > 0d {
            runtime:sleep(delay);
        }
    }
    if q.includes("mutation Login") {
        return [200, {data: {login: {token: "stand-in-token"}}}, "seaware sign-in"];
    }
    if q.includes("mutation Logout") {
        return [200, {data: {logout: true}}, "seaware sign-out"];
    }
    if sc == "seaware error" {
        return [200, {errors: [{message: "stand-in: query refused"}]}, "seaware error"];
    }
    if q.includes("mutation ClientCreate") {
        return [200, {data: {clientCreate: {clientMutationId: "m1", operationResult: "OK", result: {key: 2001}}}}, "seaware client create"];
    }
    if q.includes("mutation ClientUpdate") {
        return [200, {data: {clientUpdate: {clientMutationId: "m2", operationResult: "OK", result: {key: 1001}}}}, "seaware client update"];
    }
    if q.includes("clients(") || q.includes("clients (") || q.includes("{ clients") {
        return [200, {data: {clients: {edges: sc == "client exists" ? [{node: {key: 1001, firstName: "Trial", lastName: "Guest"}}] : []}}}, "seaware client search"];
    }
    if takeSessionError() {
        return [200, {errors: [{message: "Session context not found or expired"}]}, "seaware session gone"];
    }
    if sc.startsWith("many:") {
        int|error n = int:fromString(sc.substring(5));
        return [200, reservations(n is int ? n : 1), "seaware reservations"];
    }
    return [200, reservations(1), "seaware reservations"];
}

isolated function replyOf(string backend, string method, string zohoPath, json body) returns [int, json, string] {
    string sc = scenarioNow();
    string q = "";
    if body is map<json> && body["query"] is string {
        q = <string>body["query"];
    }
    match backend {
        "dbSystemApi" => {
            return dbReply(sc, q, body);
        }
        "zohoSysApi" => {
            return zohoReply(sc, method, zohoPath);
        }
        "reservationProcApi" => {
            return seawareReply(sc, q);
        }
        "emailSysApi" => {
            return sc == "mail down" ? [503, {message: "stand-in: mail down"}, "e-mail (refused)"]
                : [200, {status: "sent"}, "e-mail"];
        }
        "errorMail" => {
            return [200, {status: "sent"}, "error e-mail"];
        }
        "cmsContentApi" => {
            return [200, {data: {title: "Welcome aboard", body: "Hello"}}, "cms"];
        }
        "identitySupportExpApi" => {
            return sc == "ids down" ? [503, {message: "stand-in: ids down"}, "id generation (refused)"]
                : [200, {guestId: "G-1", loyaltyId: "L-1", globalGuestId: "G-1", aroyaLoyaltyId: "L-1"}, "id generation"];
        }
    }
    return [200, {}, backend];
}

listener http:Listener standinListener = new (STANDIN_PORT);

service / on standinListener {
    isolated resource function 'default [string... path](http:Request request) returns http:Response {
        string backend = path.length() > 1 ? path[1] : "";
        json|http:ClientError payload = request.getJsonPayload();
        string|http:HeaderNotFoundError zp = request.getHeader("zohoPath");
        string zohoPath = zp is string ? zp : "";
        string|http:HeaderNotFoundError auth = request.getHeader("Authorization");
        boolean query = backend == "reservationProcApi" && payload is json && payload.toJsonString().includes("reservations(");
        if query {
            enterQuery(auth is string ? auth : "");
        }
        [int, json, string] [status, out, tag] = replyOf(backend, request.method, zohoPath, payload is json ? payload : ());
        if query {
            leaveQuery(auth is string ? auth : "");
        }
        noteCall(tag);
        http:Response response = new;
        response.statusCode = status;
        if out !is () {
            response.setJsonPayload(out);
        }
        return response;
    }
}
