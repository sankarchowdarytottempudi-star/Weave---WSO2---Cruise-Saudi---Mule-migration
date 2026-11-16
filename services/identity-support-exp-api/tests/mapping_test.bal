import ballerina/test;

// The error-mapping keep: same rows as a look-up, only read at another moment.

@test:Config {}
function freshMappingIsAnsweredWithoutALookUp() returns error? {
    json rows = [{"error": "kept", "type": "T", "code": "404"}];
    keepMapping("404 /fresh", {rows: rows.cloneReadOnly(), at: epochNow()});
    // the database system API is unreachable here: an answer proves no look-up was made
    json got = check mappingRows("/fresh", 404, "t-1");
    test:assertEquals(got, rows);
}

@test:Config {}
function staleMappingIsAnsweredAtOnceAndRefreshedInTheBackground() returns error? {
    json rows = [{"error": "old", "type": "T", "code": "409"}];
    keepMapping("409 /stale", {rows: rows.cloneReadOnly(), at: epochNow() - 600d});
    json got = check mappingRows("/stale", 409, "t-2");
    test:assertEquals(got, rows, "a stale copy is answered while the fresh one is read");
}

@test:Config {}
function tooOldMappingIsReadAgainAndAFailedReadIsNotKept() {
    json rows = [{"error": "ancient"}];
    keepMapping("500 /old", {rows: rows.cloneReadOnly(), at: epochNow() - 7200d});
    json|error got = mappingRows("/old", 500, "t-3");
    test:assertTrue(got is error, "older than the stale limit: read again (and here the read fails)");
    test:assertTrue(keptMapping("500 /none") is (), "nothing is kept for a key never read");
}

@test:Config {}
function keptMappingsDoNotGrowWithoutLimit() {
    foreach int i in 0 ..< 520 {
        rememberMapping("400 /p/" + i.toString(), {rows: [], at: epochNow()});
    }
    lock {
        test:assertTrue(keptMappings.length() <= MAX_KEPT_MAPPINGS);
    }
}
