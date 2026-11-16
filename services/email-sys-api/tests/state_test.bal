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
function mailTokenKeyIsTheOldOne() {
    test:assertEquals(MAIL_TOKEN_KEY, "access_token");
}
