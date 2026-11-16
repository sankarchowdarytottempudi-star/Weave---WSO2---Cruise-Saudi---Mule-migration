import ballerina/test;
import ballerina/time;

final byte[] TITLES = "{\"query\":\"query { titles { key } }\"}".toBytes();

@test:Config {}
function onlyReferenceReadsAreCached() {
    test:assertTrue(hourlyCached("titles", TITLES));
    test:assertTrue(hourlyCached("Countries", "{\"query\":\"query { countries { key } }\"}".toBytes()));
    test:assertFalse(hourlyCached("reservation", "{\"query\":\"query { reservation(id: 1) { id } }\"}".toBytes()));
    test:assertFalse(hourlyCached("titles", "{\"query\":\"mutation { titles { key } }\"}".toBytes()));
    test:assertFalse(hourlyCached((), TITLES));
}

@test:Config {}
function aGoodAnswerIsKeptAndServed() returns error? {
    string key = refKey(TITLES);
    refPut(key, 200, "application/json", "{\"data\":{\"titles\":[{\"key\":\"MR\"}]}}".toBytes());
    [int, string, byte[]]? kept = refGet(key);
    if kept is () {
        test:assertFail("expected a kept answer");
    }
    test:assertTrue(kept[0] < 5);
    test:assertEquals(kept[1], "application/json");
    test:assertEquals(check string:fromBytes(kept[2]), "{\"data\":{\"titles\":[{\"key\":\"MR\"}]}}");
}

@test:Config {}
function failedAnswersAreNeverKept() {
    string key = refKey("{\"query\":\"query { ships { key } }\"}".toBytes());
    refPut(key, 502, "application/json", "{\"message\":\"down\"}".toBytes());
    test:assertTrue(refGet(key) is ());
    refPut(key, 200, "application/json", "{\"data\":null,\"errors\":[{\"message\":\"x\"}]}".toBytes());
    test:assertTrue(refGet(key) is ());
    refPut(key, 200, "text/plain", "not json".toBytes());
    test:assertTrue(refGet(key) is ());
}

@test:Config {}
function anOldEntryIsReportedAsStale() returns error? {
    string key = refKey("{\"query\":\"query { titles { key name } }\"}".toBytes());
    json entry = {at: time:utcNow()[0] - 4000, contentType: "application/json", body: "{\"data\":{}}"};
    check refStore.put(key, entry.toJsonString(), 0);
    [int, string, byte[]]? kept = refGet(key);
    if kept is () {
        test:assertFail("expected a kept answer");
    }
    test:assertTrue(kept[0] >= hourlyCacheSeconds);
}

@test:Config {}
function keysDifferPerQueryAndVariables() {
    test:assertNotEquals(refKey(TITLES), refKey("{\"query\":\"query { titles { key } }\",\"variables\":{\"a\":1}}".toBytes()));
}
