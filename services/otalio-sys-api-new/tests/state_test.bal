import ballerina/lang.runtime;
import ballerina/test;

// The old object store's values, with Redis switched off: kept in memory, with their time to live.

@test:Config {}
function stateKeptInMemoryWhenRedisIsOff() returns error? {
    test:assertEquals(state.location(), "memory");
    check state.put("k-test", "v");
    test:assertEquals(check state.get("k-test"), "v");
    test:assertTrue(check state.contains("k-test"));
    check state.remove("k-test");
    test:assertEquals(check state.get("k-test"), ());
}

@test:Config {}
function stateValueExpiresAfterItsTimeToLive() returns error? {
    check state.put("k-ttl", "v", 1);
    test:assertEquals(check state.get("k-ttl"), "v");
    runtime:sleep(1.3);
    test:assertEquals(check state.get("k-ttl"), ());
}

@test:Config {}
function stateClearRemovesEverything() returns error? {
    check state.put("a", "1");
    check state.put("b", "2", 60);
    check state.clear();
    test:assertEquals(check state.get("a"), ());
    test:assertEquals(check state.get("b"), ());
}

@test:Config {}
function keptRefreshTokenIsReadBack() returns error? {
    check state.put(REFRESH_KEY, "ref-a|1700000999", 60);
    [string, int] kept = check keptRefresh();
    test:assertEquals(kept[0], "ref-a");
    test:assertEquals(kept[1], 1700000999);
    check state.remove(REFRESH_KEY);
    test:assertTrue(keptRefresh() is error);
    test:assertEquals(REFRESH_KEY, "refresh_token");
}
