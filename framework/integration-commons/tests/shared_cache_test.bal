import ballerina/lang.runtime;
import ballerina/test;
import ballerina/time;

// SharedCache: hits, misses, errors never kept, coalescing, release of waiters when the leader
// fails or vanishes, and a value kept by another copy of the service read from the shared store.

isolated int fetches = 0;

isolated function fetchCount() returns int {
    lock {
        return fetches;
    }
}

isolated function resetFetches() {
    lock {
        fetches = 0;
    }
}

isolated function countedFetch(string value, boolean keep = true, decimal delay = 0) returns CacheFill {
    lock {
        fetches += 1;
    }
    if delay > 0d {
        runtime:sleep(delay);
    }
    return {value, keep};
}

@test:Config {}
function sharedCacheMissThenHit() returns error? {
    resetFetches();
    SharedCache c = new (60);
    CacheAnswer one = check c.getOrFetch("k", isolated function () returns CacheFill|error => countedFetch("v1"));
    CacheAnswer two = check c.getOrFetch("k", isolated function () returns CacheFill|error => countedFetch("v2"));
    test:assertEquals(one, {value: "v1", origin: "fetched"});
    test:assertEquals(two, {value: "v1", origin: "cache"});
    test:assertEquals(fetchCount(), 1);
}

@test:Config {}
function sharedCacheKeysAreSeparate() returns error? {
    SharedCache c = new (60);
    _ = check c.getOrFetch("guest:1", isolated function () returns CacheFill|error => {value: "one"});
    CacheAnswer other = check c.getOrFetch("guest:2", isolated function () returns CacheFill|error => {value: "two"});
    test:assertEquals(other.value, "two", "a value is never served for another key");
}

@test:Config {}
function sharedCacheErrorsAndUnkeptValuesAreNotKept() returns error? {
    resetFetches();
    SharedCache c = new (60);
    CacheAnswer|error failed = c.getOrFetch("e", isolated function () returns CacheFill|error {
        _ = countedFetch("x");
        return error("backend down");
    });
    test:assertTrue(failed is error);
    CacheAnswer refused = check c.getOrFetch("e", isolated function () returns CacheFill|error => countedFetch("refused", false));
    test:assertEquals(refused.value, "refused");
    CacheAnswer good = check c.getOrFetch("e", isolated function () returns CacheFill|error => countedFetch("good"));
    test:assertEquals(good, {value: "good", origin: "fetched"});
    test:assertEquals(fetchCount(), 3, "neither the error nor the unkept answer was served from the cache");
}

@test:Config {}
function sharedCacheExpires() returns error? {
    resetFetches();
    SharedCache c = new (1);
    _ = check c.getOrFetch("t", isolated function () returns CacheFill|error => countedFetch("old"));
    runtime:sleep(1.2);
    CacheAnswer fresh = check c.getOrFetch("t", isolated function () returns CacheFill|error => countedFetch("new"));
    test:assertEquals(fresh, {value: "new", origin: "fetched"});
    test:assertEquals(fetchCount(), 2);
}

@test:Config {}
function sharedCacheOffAlwaysFetches() returns error? {
    resetFetches();
    SharedCache c = new (0);
    _ = check c.getOrFetch("o", isolated function () returns CacheFill|error => countedFetch("a"));
    _ = check c.getOrFetch("o", isolated function () returns CacheFill|error => countedFetch("b"));
    test:assertEquals(fetchCount(), 2);
    test:assertFalse(c.isOn());
    test:assertEquals(c.describe(), "off");
    test:assertEquals(c.get("o"), ());
}

isolated function burst(SharedCache c, string key, int n, isolated function () returns CacheFill|error fetcher) returns CacheAnswer[]|error {
    future<CacheAnswer|error>[] calls = [];
    foreach int i in 0 ..< n {
        future<CacheAnswer|error> f = start c.getOrFetch(key, fetcher);
        calls.push(f);
    }
    CacheAnswer[] answers = [];
    foreach future<CacheAnswer|error> f in calls {
        CacheAnswer a = check wait f;
        answers.push(a);
    }
    return answers;
}

@test:Config {}
function sharedCacheTenIdenticalRequestsMakeOneFetch() returns error? {
    resetFetches();
    SharedCache c = new (60);
    CacheAnswer[] answers = check burst(c, "burst", 10,
            isolated function () returns CacheFill|error => countedFetch("shared", true, 0.4));
    foreach CacheAnswer a in answers {
        test:assertEquals(a.value, "shared");
    }
    test:assertEquals(fetchCount(), 1, "10 identical requests at the same time make one fetch");
    test:assertEquals(answers.filter(a => a.origin == "fetched").length(), 1);
}

@test:Config {}
function sharedCacheWaitersAreReleasedWhenTheLeaderFails() returns error? {
    resetFetches();
    SharedCache c = new (60, (), 5);
    // the leader fails after 0.3 s; the others must not hang: each fetches for itself and gets its answer
    CacheAnswer[] answers = check burst(c, "fails", 4, isolated function () returns CacheFill|error {
        int n;
        lock {
            fetches += 1;
            n = fetches;
        }
        runtime:sleep(0.3);
        if n == 1 {
            return {value: "leader refused", keep: false};
        }
        return {value: "ok"};
    });
    test:assertEquals(answers.length(), 4);
    test:assertTrue(fetchCount() >= 2, "the waiters fetched after the leader kept nothing");
}

@test:Config {}
function sharedCacheAbandonedMarkExpires() returns error? {
    SharedCache c = new (60, (), 0.5);
    // a leader that never comes back: its mark is never released
    decimal? mark = c.lead("gone");
    test:assertTrue(mark is decimal);
    test:assertEquals(c.lead("gone"), (), "the mark holds while it is young");
    decimal started = time:monotonicNow();
    test:assertEquals(c.awaitShared("gone"), ());
    test:assertTrue(time:monotonicNow() - started < 2d, "a waiter is released when the mark expires");
    test:assertTrue(c.lead("gone") is decimal, "an expired mark is taken over");
}

// Another copy of the service fetched the value: this copy has nothing in memory and reads it from
// the shared store (the path that crashed in cms-proc-api on 2026-11-17).
@test:Config {}
function sharedCacheValueKeptByAnotherCopyIsServed() returns error? {
    resetFetches();
    MemoryCacheStore shared = new;
    SharedCache copyA = new (60, shared);
    SharedCache copyB = new (60, shared);
    _ = check copyA.getOrFetch("x", isolated function () returns CacheFill|error => countedFetch("from A"));
    CacheAnswer b = check copyB.getOrFetch("x", isolated function () returns CacheFill|error => countedFetch("from B"));
    test:assertEquals(b, {value: "from A", origin: "cache"});
    test:assertEquals(fetchCount(), 1, "served from the shared store, not fetched again");
    // and once more from B's own memory copy
    test:assertEquals(copyB.get("x"), "from A");
    test:assertEquals(copyA.describe(), "shared memory, 60 s");
}

@test:Config {}
function sharedCacheStoreValueKeepsItsAge() returns error? {
    MemoryCacheStore shared = new;
    SharedCache copyA = new (1, shared);
    SharedCache copyB = new (1, shared);
    copyA.put("age", "v");
    runtime:sleep(0.6);
    test:assertEquals(copyB.get("age"), "v");
    runtime:sleep(0.6);
    test:assertEquals(copyB.get("age"), (), "a copy never keeps a value longer than the copy that fetched it");
}

@test:Config {}
function sharedCacheRemoveIfValue() returns error? {
    MemoryCacheStore shared = new;
    SharedCache copyA = new (60, shared);
    SharedCache copyB = new (60, shared);
    copyA.put("token", "t1");
    test:assertFalse(copyB.removeIfValue("token", "t0"), "a newer value is not removed");
    test:assertTrue(copyB.removeIfValue("token", "t1"));
    SharedCache copyC = new (60, shared);
    test:assertEquals(copyC.get("token"), ());
    copyA.remove("token");
    test:assertEquals(copyA.get("token"), ());
}

@test:Config {}
function sharedCacheMemoryBudgetStartsOver() {
    SharedCache c = new (60, (), 30, 10);
    c.put("a", "123456");
    c.put("b", "123456");
    test:assertEquals(c.get("a"), (), "the memory copy started over when full");
    test:assertEquals(c.get("b"), "123456");
}

@test:Config {}
function sharedCacheWithoutRedis() returns error? {
    SharedCache c = check newSharedCache({enabled: false}, "test:", 60);
    test:assertEquals(c.describe(), "memory, 60 s");
    test:assertTrue(c.isOn());
}
