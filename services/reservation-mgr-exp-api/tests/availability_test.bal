// Availability cache: identical requests at the same time make one backend call, answers are kept
// per request inputs and per credential, errors are never kept, other operations are untouched.
import ballerina/http;
import ballerina/lang.runtime;
import ballerina/test;

import aroya/integration_commons as commons;

isolated map<int> backendCalls = {};

isolated function callsFor(string tag) returns int {
    lock {
        return backendCalls[tag] ?: 0;
    }
}

listener http:Listener standinListener = new (19882);

service /reservation\-common\-proc\-api/v1 on standinListener {
    isolated resource function post integration\-tasks(http:Request request) returns http:Response {
        string body = "";
        byte[]|http:ClientError raw = request.getBinaryPayload();
        if raw is byte[] {
            string|error text = string:fromBytes(raw);
            body = text is string ? text : "";
        }
        // the test tag is the voyage variable
        int? at = body.indexOf("TAG-");
        string tag = at is int ? body.substring(at, at + 9) : "none";
        int n;
        lock {
            n = (backendCalls[tag] ?: 0) + 1;
            backendCalls[tag] = n;
        }
        runtime:sleep(0.4);
        http:Response r = new;
        if body.includes("FAIL") {
            r.statusCode = 500;
            r.setJsonPayload({message: "stand-in failure"});
        } else if body.includes("GQLERR") {
            r.setJsonPayload({data: (), errors: [{message: "stand-in GraphQL error"}]});
        } else {
            r.setJsonPayload({data: {availableCabinCategories: [{code: "A1", call: n}]}});
        }
        return r;
    }
}

function bodyOf(string tag, string op = "AvailableCabinCategories", string root = "availableCabinCategories") returns string =>
    string `{"query":"query ${op}($voyage: String) { ${root}(voyage: $voyage) { code } }","variables":{"voyage":"${tag}","adults":2,"currency":"SAR"}}`;

function ctxOf(string body, string auth = "Bearer gateway", string seaware = "") returns RequestContext & readonly {
    map<string> headers = {"Content-Type": "application/json", "correlationId": "test"};
    if auth != "" {
        headers["Authorization"] = auth;
    }
    if seaware != "" {
        headers["X-Seaware-Authorization"] = seaware;
    }
    json payload = jsonOf(body.toBytes());
    string query = queryOf(payload);
    RequestContext c = {
        correlationId: "test",
        version: "v1",
        endpoint: "/reservation-mgr-exp-api/v1/integration-tasks",
        body: body.toBytes(),
        payload,
        operationType: commons:operationTypeOf(query),
        operationName: commons:operationNameOf(query),
        rootField: commons:rootFieldOf(query),
        headers,
        authorization: auth,
        forwardedFor: "",
        targetHeader: ""
    };
    return c.cloneReadOnly();
}

function textOfOutcome(Outcome o) returns string {
    byte[]? raw = o.raw;
    if raw is byte[] {
        string|error t = string:fromBytes(raw);
        return t is string ? t : "";
    }
    return o.body.toJsonString();
}

@test:Config {}
function tenIdenticalRequestsMakeOneBackendCall() returns error? {
    RequestContext & readonly ctx = ctxOf(bodyOf("TAG-00001"));
    test:assertTrue(availabilityCached(ctx));
    future<Outcome>[] calls = [];
    foreach int i in 0 ..< 10 {
        future<Outcome> f = start processAvailability(ctx, true);
        calls.push(f);
    }
    string first = "";
    foreach future<Outcome> f in calls {
        Outcome o = check wait f;
        test:assertTrue(o.ok);
        test:assertEquals(o.status, 200);
        if first == "" {
            first = textOfOutcome(o);
        }
        test:assertEquals(textOfOutcome(o), first, "every caller gets the same answer");
    }
    test:assertEquals(callsFor("TAG-00001"), 1, "10 identical requests at the same time: one backend call");
    // and the next one within the cache time is answered from the cache
    Outcome again = processAvailability(ctx, false);
    test:assertTrue(again.ok);
    test:assertEquals(again.body.toJsonString(), jsonOf(first.toBytes()).toJsonString());
    test:assertEquals(callsFor("TAG-00001"), 1);
}

@test:Config {}
function differentInputsAreDifferentAnswers() {
    _ = processAvailability(ctxOf(bodyOf("TAG-00002")), true);
    _ = processAvailability(ctxOf(bodyOf("TAG-00002").substring(0, bodyOf("TAG-00002").length() - 1) + ",\"promo\":\"P1\"}"), true);
    test:assertEquals(callsFor("TAG-00002"), 2, "another variable (promo) is another answer");
}

@test:Config {}
function differentCredentialsNeverShare() {
    _ = processAvailability(ctxOf(bodyOf("TAG-00003"), "Bearer gateway", "agent-session-1"), true);
    _ = processAvailability(ctxOf(bodyOf("TAG-00003"), "Bearer gateway", "agent-session-2"), true);
    _ = processAvailability(ctxOf(bodyOf("TAG-00003"), "Bearer other-caller"), true);
    test:assertEquals(callsFor("TAG-00003"), 3, "an answer is never shared between different Seaware credentials");
    _ = processAvailability(ctxOf(bodyOf("TAG-00003"), "Bearer gateway", "agent-session-1"), true);
    test:assertEquals(callsFor("TAG-00003"), 3, "the same credential and inputs share the kept answer");
}

@test:Config {}
function errorsAreNeverKept() {
    Outcome failed = processAvailability(ctxOf(bodyOf("TAG-FAIL1")), true);
    test:assertFalse(failed.ok);
    test:assertEquals(failed.status, 500);
    _ = processAvailability(ctxOf(bodyOf("TAG-FAIL1")), true);
    test:assertEquals(callsFor("TAG-FAIL1"), 2, "an error answer is never kept");
    Outcome gql = processAvailability(ctxOf(bodyOf("TAG-GQLERR")), true);
    test:assertTrue(gql.ok, "a GraphQL error is passed on as before");
    _ = processAvailability(ctxOf(bodyOf("TAG-GQLERR")), true);
    test:assertEquals(callsFor("TAG-GQLER"), 2, "an answer with GraphQL errors is never kept");
}

@test:Config {}
function waitersAreReleasedWhenTheLeaderFails() returns error? {
    RequestContext & readonly ctx = ctxOf(bodyOf("TAG-FAIL2"));
    future<Outcome>[] calls = [];
    foreach int i in 0 ..< 4 {
        future<Outcome> f = start processAvailability(ctx, true);
        calls.push(f);
    }
    foreach future<Outcome> f in calls {
        Outcome o = check wait f;
        test:assertEquals(o.status, 500, "every caller gets an answer");
    }
}

@test:Config {}
function otherOperationsAreNotCached() {
    test:assertFalse(availabilityCached(ctxOf(bodyOf("TAG-00004", "Reservation", "reservation"))));
    test:assertFalse(availabilityCached(ctxOf("{\"query\":\"mutation AvailableCabins { availableCabins { code } }\"}")));
    test:assertTrue(availabilityCached(ctxOf(bodyOf("TAG-00004", "AvailableCabins", "availableCabins"))));
}

final http:Client expClient = check new ("http://localhost:19881/reservation-mgr-exp-api", {timeout: 30});

function postTask(string body, int i) returns http:Response|error {
    http:Request request = new;
    request.setTextPayload(body, "application/json");
    request.setHeader("correlationId", "http-" + i.toString());
    request.setHeader("Authorization", "Bearer gateway");
    return expClient->post("/v1/integration-tasks", request);
}

@test:Config {}
function tenParallelHttpRequestsMakeOneBackendCall() returns error? {
    string body = bodyOf("TAG-00005");
    future<http:Response|error>[] calls = [];
    foreach int i in 0 ..< 10 {
        future<http:Response|error> f = start postTask(body, i);
        calls.push(f);
    }
    foreach future<http:Response|error> f in calls {
        http:Response r = check wait f;
        test:assertEquals(r.statusCode, 200);
        json answer = check r.getJsonPayload();
        json categories = check answer.data.availableCabinCategories;
        test:assertEquals(categories, [{code: "A1", call: 1}]);
    }
    test:assertEquals(callsFor("TAG-00005"), 1);
}
