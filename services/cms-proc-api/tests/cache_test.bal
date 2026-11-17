import ballerina/http;
import ballerina/lang.runtime;
import ballerina/test;

type Source record {|
    int calls;
    int status;
    string body;
    decimal delay;
|};

isolated Source src = {calls: 0, status: 200, body: "{}", delay: 0};

isolated function fakeSource() returns http:Response|http:ClientError {
    decimal d;
    int s;
    string b;
    lock {
        src.calls += 1;
        d = src.delay;
        s = src.status;
        b = src.body;
    }
    if d > 0d {
        runtime:sleep(d);
    }
    http:Response r = new;
    r.statusCode = s;
    if b != "" {
        r.setBinaryPayload(b.toBytes());
        r.setHeader("content-type", "application/json; charset=utf-8");
    }
    return r;
}

isolated function setSource(int s, string b, decimal d = 0) {
    lock {
        src = {calls: 0, status: s, body: b, delay: d};
    }
}

isolated function callCount() returns int {
    lock {
        return src.calls;
    }
}

isolated function bodyOf(http:Response r) returns string {
    byte[]|http:ClientError b = r.getBinaryPayload();
    if b is byte[] {
        string|error t = string:fromBytes(b);
        return t is string ? t : "";
    }
    return "";
}

@test:Config {}
function missThenHitSameAnswer() returns error? {
    setSource(200, "{\"a\":\"first\"}");
    http:Response one = cachedRelay("t:hit", fakeSource, "c1", "The content source");
    http:Response two = cachedRelay("t:hit", fakeSource, "c2", "The content source");
    test:assertEquals(callCount(), 1, "second answer must come from the cache");
    test:assertEquals(two.statusCode, 200);
    test:assertEquals(bodyOf(two), bodyOf(one));
    test:assertEquals(check two.getHeader("content-type"), "application/json; charset=utf-8");
}

@test:Config {}
function errorsAreNotKept() {
    setSource(503, "{\"e\":1}");
    http:Response one = cachedRelay("t:err", fakeSource, "c1", "The content source");
    _ = cachedRelay("t:err", fakeSource, "c2", "The content source");
    test:assertEquals(one.statusCode, 503);
    test:assertEquals(callCount(), 2, "an error answer must never be served from the cache");
}

@test:Config {}
function emptyBodiesAreNotKept() {
    setSource(200, "");
    _ = cachedRelay("t:empty", fakeSource, "c1", "The content source");
    _ = cachedRelay("t:empty", fakeSource, "c2", "The content source");
    test:assertEquals(callCount(), 2);
}

@test:Config {}
function staleIsServedThenRefreshedThenExpired() {
    setSource(200, "{\"v\":1}");
    _ = cachedRelay("t:stale", fakeSource, "c1", "The content source");
    runtime:sleep(2.2);                       // past the cache time, within the grace time
    setSource(200, "{\"v\":2}");
    http:Response stale = cachedRelay("t:stale", fakeSource, "c2", "The content source");
    test:assertEquals(bodyOf(stale), "{\"v\":1}", "within the grace time the kept answer is served at once");
    runtime:sleep(0.5);                       // the background refresh has run
    test:assertEquals(callCount(), 1);
    http:Response fresh = cachedRelay("t:stale", fakeSource, "c3", "The content source");
    test:assertEquals(bodyOf(fresh), "{\"v\":2}");
    runtime:sleep(4.5);                       // older than cache time + grace: fetched again
    setSource(200, "{\"v\":3}");
    http:Response again = cachedRelay("t:stale", fakeSource, "c4", "The content source");
    test:assertEquals(bodyOf(again), "{\"v\":3}");
    test:assertEquals(callCount(), 1);
}

@test:Config {}
function identicalMissesShareOneFetch() returns error? {
    setSource(200, "{\"shared\":true}", 0.5);
    future<http:Response> f0 = start cachedRelay("t:burst", fakeSource, "c0", "The content source");
    future<http:Response> f1 = start cachedRelay("t:burst", fakeSource, "c1", "The content source");
    future<http:Response> f2 = start cachedRelay("t:burst", fakeSource, "c2", "The content source");
    future<http:Response> f3 = start cachedRelay("t:burst", fakeSource, "c3", "The content source");
    future<http:Response> f4 = start cachedRelay("t:burst", fakeSource, "c4", "The content source");
    future<http:Response> f5 = start cachedRelay("t:burst", fakeSource, "c5", "The content source");
    http:Response r0 = check wait f0;
    http:Response r1 = check wait f1;
    http:Response r2 = check wait f2;
    http:Response r3 = check wait f3;
    http:Response r4 = check wait f4;
    http:Response r5 = check wait f5;
    http:Response[] all = [r0, r1, r2, r3, r4, r5];
    foreach http:Response r in all {
        test:assertEquals(r.statusCode, 200);
        test:assertEquals(bodyOf(r), "{\"shared\":true}");
    }
    test:assertEquals(callCount(), 1, "6 identical concurrent misses must make one call to the source");
}

// Another copy of the service fetched the answer: this copy has nothing in memory and reads it
// back from the shared store (the path that crashed and left callers hanging, 2026-11-17).
@test:Config {}
function answerKeptByAnotherCopyIsServed() returns error? {
    setSource(200, "{\"a\":\"shared\"}");
    _ = cachedRelay("t:shared", fakeSource, "c1", "The content source");
    lock {
        memory.copies.removeAll();
        memory.bytes = 0;
    }
    http:Response two = cachedRelay("t:shared", fakeSource, "c2", "The content source");
    test:assertEquals(two.statusCode, 200);
    test:assertEquals(bodyOf(two), "{\"a\":\"shared\"}");
    test:assertEquals(callCount(), 1, "served from the shared store, not fetched again");
}

// Five identical requests at the same moment: one fetch, every caller gets the answer quickly.
@test:Config {}
function fiveIdenticalParallelRequestsAllAnswered() returns error? {
    setSource(200, "{\"a\":\"burst\"}", 0.5);
    future<http:Response>[] calls = [];
    foreach int i in 0 ..< 5 {
        future<http:Response> f = start cachedRelay("t:burst5", fakeSource, "c" + i.toString(), "The content source");
        calls.push(f);
    }
    foreach future<http:Response> f in calls {
        http:Response r = check wait f;
        test:assertEquals(r.statusCode, 200);
        test:assertEquals(bodyOf(r), "{\"a\":\"burst\"}");
    }
    test:assertEquals(callCount(), 1, "one fetch shared by all five");
}

// A fetch mark that was never cleared (its request died) must not hold later requests.
@test:Config {}
function abandonedMarkDoesNotHoldRequests() returns error? {
    setSource(200, "{\"a\":\"after\"}");
    lock {
        inFlight["t:abandoned"] = 0;
    }
    http:Response r = cachedRelay("t:abandoned", fakeSource, "c1", "The content source");
    test:assertEquals(r.statusCode, 200);
    test:assertEquals(bodyOf(r), "{\"a\":\"after\"}");
}
