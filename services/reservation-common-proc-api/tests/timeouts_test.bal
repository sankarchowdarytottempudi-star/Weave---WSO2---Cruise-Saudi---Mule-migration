import ballerina/test;

@test:Config {}
function mutationGoesToTheWriteClient() {
    test:assertTrue(isMutation("{\"query\":\"mutation Store { reservationStore(id: 1) { id } }\"}".toBytes()));
    test:assertTrue(isMutation("{\"query\":\"# comment\\nmutation { reservationStore(id: 1) { id } }\"}".toBytes()));
}

@test:Config {}
function queriesAndJunkAreReads() {
    test:assertFalse(isMutation("{\"query\":\"query { titles { key } }\"}".toBytes()));
    test:assertFalse(isMutation("{\"query\":\"{ titles { key } }\"}".toBytes()));
    test:assertFalse(isMutation("not json".toBytes()));
    test:assertFalse(isMutation([0xff, 0xfe]));
}

@test:Config {}
function readAndWriteLimits() {
    // the tests' Config.toml shortens the read limits; writes keep their own, longer limit
    test:assertTrue(sysWriteTimeoutSeconds > sysTimeoutSeconds);
    test:assertEquals(sysWriteTimeoutSeconds, 60d);
}
