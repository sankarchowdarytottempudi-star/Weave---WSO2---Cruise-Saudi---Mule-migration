import ballerina/http;
import ballerina/lang.runtime;
import ballerina/test;

// A stand-in for the Seaware System API and the Process cache on 127.0.0.2 (made-up data only).
// It keeps what it received (path, body bytes, headers) so tests can check what was sent.
listener http:Listener sysStandIn = new (18965, host = "127.0.0.2");

isolated int logins = 0;
isolated boolean loginWithoutToken = false;
type Seen record {|
    string path = "";
    byte[] body = [];
    map<string> headers = {};
|};

isolated Seen seen = {};

isolated function keep(string path, http:Request req) returns byte[] {
    byte[] body = (checkpanic req.getBinaryPayload()).clone();
    map<string> h = {};
    foreach string name in ["Authorization", "X-Seaware-Authorization", "operationName", "correlationId", "Content-Type"] {
        string|http:HeaderNotFoundError v = req.getHeader(name);
        if v is string {
            h[name] = v;
        }
    }
    Seen now = {path: path, body: body.clone(), headers: h.clone()};
    lock {
        seen = now.clone();
    }
    return body;
}

isolated function standInAnswer(string path, http:Request req) returns http:Response {
    byte[] body = keep(path, req);
    string text = checkpanic string:fromBytes(body);
    http:Response res = new;
    if text.includes("SLOW") {
        runtime:sleep(3);
    }
    if text.includes("mutation Login") {
        boolean without;
        lock {
            without = loginWithoutToken;
        }
        int n;
        lock {
            logins += 1;
            n = logins;
        }
        res.setJsonPayload(without ? {data: {login: {}}} : {data: {login: {token: "stand-in-token-" + n.toString()}}});
        return res;
    }
    string|http:HeaderNotFoundError auth = req.getHeader("Authorization");
    if auth is string && auth == "stale-token" {
        res.statusCode = 401;
        res.setJsonPayload({message: "token refused"});
        return res;
    }
    if text.includes("FAIL500") {
        res.statusCode = 500;
        res.setJsonPayload({message: "stand-in failure", code: "E-500"});
        return res;
    }
    res.setJsonPayload({data: {'from: path}});
    return res;
}

service / on sysStandIn {
    isolated resource function post seaware\-sys\-api/v1/integration\-tasks(http:Request req) returns http:Response
        => standInAnswer("sys", req);
    isolated resource function post seaware\-cache\-proc\-api/v1/cache(http:Request req) returns http:Response
        => standInAnswer("cache", req);
}

isolated function loginCount() returns int {
    lock {
        return logins;
    }
}

isolated function setLoginWithoutToken(boolean value) {
    lock {
        loginWithoutToken = value;
    }
}

isolated function lastCall() returns [string, byte[], map<string>] {
    Seen s;
    lock {
        s = seen.clone();
    }
    return [s.path, s.body, s.headers];
}

@test:Config {}
function signsInOnceAndKeepsTheToken() returns error? {
    check state.remove(SEAWARE_TOKEN_KEY);
    int before = loginCount();
    string first = check seawareToken("t-1", false);
    string again = check seawareToken("t-2", false);
    test:assertEquals(again, first);
    test:assertEquals(loginCount(), before + 1);
    test:assertEquals(check state.get(SEAWARE_TOKEN_KEY), first);
}

@test:Config {dependsOn: [signsInOnceAndKeepsTheToken]}
function aRefusedTokenIsReplaced() returns error? {
    string kept = check seawareToken("t-3", false);
    string fresh = check seawareToken("t-4", true);
    test:assertNotEquals(fresh, kept);
    test:assertEquals(check state.get(SEAWARE_TOKEN_KEY), fresh);
}

@test:Config {}
function loginAnswerWithoutTokenIsAnError() {
    test:assertTrue(tokenOfLogin({data: {login: {}}}) is error);
    test:assertTrue(tokenOfLogin({data: {login: {token: ""}}}) is error);
    test:assertTrue(tokenOfLogin({data: {}}) is error);
    test:assertEquals(tokenOfLogin({data: {login: {token: "x"}}}), "x");
}

@test:Config {}
function stateValueExpires() returns error? {
    test:assertEquals(state.location(), "memory");
    check state.put("k-ttl", "v", 1);
    runtime:sleep(1.3);
    test:assertEquals(check state.get("k-ttl"), ());
}

@test:Config {}
function stateKeepsRemovesAndClears() returns error? {
    check state.put("k-a", "1");
    check state.put("k-b", "2", 60);
    test:assertTrue(check state.contains("k-a"));
    test:assertEquals(check state.get("k-b"), "2");
    check state.remove("k-a");
    test:assertFalse(check state.contains("k-a"));
    test:assertEquals(check state.get("k-missing"), ());
    check state.clear();
    test:assertFalse(check state.contains("k-b"));
    check state.remove("k-never-there");
}
