import ballerina/sql;
import ballerina/test;

import aroya/integration_commons as commons;

@test:Config {}
function rowsBecomeJson() {
    record {} row = {
        "id": "7b0c2a52-58a0-4c57-9f0c-3a1b5a6d1c11",
        "n": 7,
        "amount": 12.340d,
        "ratio": 1.5,
        "ok": true,
        "missing": (),
        "created": "2026-03-04 10:15:30.123456",
        "seen": "2026-03-04 08:15:00.0",
        "day": "2026-03-04",
        "payload": "{\"a\": 1}",
        "bytes": <byte[]>[1, 2, 255],
        "tags": ["a", "b"],
        "numbers": [1, 2]
    };
    test:assertEquals(rowOf(row), {
                                      "id": "7b0c2a52-58a0-4c57-9f0c-3a1b5a6d1c11",
                                      "n": 7,
                                      "amount": 12.340d,
                                      "ratio": 1.5,
                                      "ok": true,
                                      "missing": (),
                                      "created": "2026-03-04T10:15:30.123456",
                                      "seen": "2026-03-04T08:15:00",
                                      "day": "2026-03-04",
                                      "payload": "{\"a\": 1}",
                                      "bytes": "AQL/",
                                      "tags": ["a", "b"],
                                      "numbers": [1, 2]
                                  });
}

@test:Config {}
function onlyDriverTimestampsAreRewritten() {
    test:assertEquals(isoStampOf("2026-03-04 10:15:30.0"), "2026-03-04T10:15:30");
    test:assertEquals(isoStampOf("2026-03-04 10:15:30.120"), "2026-03-04T10:15:30.12");
    test:assertEquals(isoStampOf("2026-03-04 10:15:30"), "2026-03-04 10:15:30");
    test:assertEquals(isoStampOf("on 2026-03-04 10:15:30.0 we met"), "on 2026-03-04 10:15:30.0 we met");
    test:assertEquals(isoStampOf("hello"), "hello");
    test:assertEquals(isoStampOf(""), "");
}

@test:Config {}
function changedRowsAnswer() {
    test:assertEquals(changedOf(3), {"affectedRows": 3, "generatedKeys": {}});
    test:assertEquals(changedOf(()), {"affectedRows": 0, "generatedKeys": {}});
}

@test:Config {}
function errorBodyKeepsTheOldMembers() {
    commons:ErrorEnvelope body = envelopeOf(refusal("UNAUTHORIZED", 401, "Invalid operation or not implemented: select"), "c-1");
    test:assertEquals(body.statusCode, 401);
    test:assertEquals(body.'error, "UNAUTHORIZED");
    test:assertEquals(body.message, "Invalid operation or not implemented: select");
    test:assertEquals(body.correlationId, "c-1");
    test:assertEquals(body.targetError, "Invalid operation or not implemented: select");
    test:assertEquals(body.toJson().toJsonString().includes("\"timestamp\""), true);
}

@test:Config {}
function aRefusedStatementKeepsTheDatabaseMessage() {
    sql:DatabaseError failure = error sql:DatabaseError(
        "Error while executing SQL query: SELECT * FROM secret_table WHERE a = ? . ERROR: relation \"nope\" does not exist\n  Position: 15.",
        errorCode = 0, sqlState = "42P01");
    Refusal result = databaseRefusal(failure);
    test:assertEquals(result.detail().status, 500);
    test:assertEquals(result.detail().errorType, "QUERY_EXECUTION");
    test:assertEquals(result.message(), "ERROR: relation \"nope\" does not exist Position: 15 (SQLSTATE 42P01)");
    test:assertFalse(result.message().includes("secret_table"));
}

@test:Config {}
function aConnectionFailureGetsAFixedText() {
    sql:DatabaseError refusedLogin = error sql:DatabaseError(
        "Error while executing SQL query: x. FATAL: password authentication failed for user \"someone\".",
        errorCode = 0, sqlState = "28P01");
    Refusal result = databaseRefusal(refusedLogin);
    test:assertEquals(result.detail().errorType, "CONNECTIVITY");
    test:assertEquals(result.detail().status, 500);
    test:assertFalse(result.message().includes("someone"));

    sql:Error plain = error sql:ApplicationError("Connection to db.internal:5432 refused");
    Refusal other = databaseRefusal(plain);
    test:assertEquals(other.detail().errorType, "CONNECTIVITY");
    test:assertFalse(other.message().includes("db.internal"));
}

@test:Config {}
function missingSettingsAre503() {
    Refusal result = notConfigured(["database.host", "guest.password"]);
    test:assertEquals(result.detail().status, 503);
    test:assertEquals(result.detail().errorType, "SERVICE_UNAVAILABLE");
    test:assertEquals(result.message(), "The database settings are not set: database.host, guest.password");
}

@test:Config {}
function theKindOfConnectionFailureIsTold() {
    sql:Error refused = error sql:ApplicationError(
        "Error in SQL connector configuration: Failed to initialize pool: Connection to db.internal:5432 refused. Check that the hostname and port are correct.");
    test:assertEquals(connectFailureOf(refused), "refused");
    Refusal told = databaseRefusal(refused);
    test:assertEquals(told.detail().errorType, "CONNECTIVITY");
    test:assertEquals(told.detail().status, 500);
    test:assertTrue(told.message().startsWith("The database could not be reached with the configured address and account: "));
    test:assertTrue(told.message().includes("refused the connection"));
    test:assertFalse(told.message().includes("db.internal"));

    sql:Error slow = error sql:ApplicationError("Failed to initialize pool: The connection attempt failed.",
        error("connect timed out"));
    test:assertEquals(connectFailureOf(slow), "no-answer");
    sql:Error noName = error sql:ApplicationError("The connection attempt failed.", error("java.net.UnknownHostException: db.internal"));
    test:assertEquals(connectFailureOf(noName), "unknown-host");
    test:assertFalse(databaseRefusal(noName).message().includes("db.internal"));

    sql:DatabaseError login = error sql:DatabaseError("FATAL: password authentication failed for user \"someone\".",
        errorCode = 0, sqlState = "28P01");
    test:assertEquals(connectFailureOf(login), "login");
    test:assertFalse(databaseRefusal(login).message().includes("someone"));
    sql:Error notAllowed = error sql:ApplicationError(
        "Failed to initialize pool: FATAL: no pg_hba.conf entry for host \"10.0.0.1\", user \"someone\", database \"main\", no encryption");
    test:assertEquals(connectFailureOf(notAllowed), "login");
    test:assertFalse(databaseRefusal(notAllowed).message().includes("10.0.0.1"));

    sql:DatabaseError noDb = error sql:DatabaseError("FATAL: database \"main\" does not exist", errorCode = 0, sqlState = "3D000");
    test:assertEquals(connectFailureOf(noDb), "database-name");
    sql:DatabaseError full = error sql:DatabaseError("FATAL: sorry, too many clients already", errorCode = 0, sqlState = "53300");
    test:assertEquals(connectFailureOf(full), "busy");

    sql:Error other = error sql:ApplicationError("something else");
    test:assertEquals(connectFailureOf(other), "unknown");
    test:assertEquals(databaseRefusal(other).message(), "The database could not be reached with the configured address and account");
    test:assertEquals(notReachable().message(), "The database could not be reached with the configured address and account");
}
