import ballerina/test;

@test:Config {}
function requestKeepsTheOldDefaults() returns error? {
    DbRequest empty = check requestOf(());
    test:assertEquals(empty, {connectionKey: "", operation: "", query: "", params: {}});

    DbRequest full = check requestOf({
                                         "connectionKey": "PG_Guest",
                                         "operation": "Select",
                                         "query": "SELECT 1",
                                         "params": {"a": 1},
                                         "extra": true
                                     });
    test:assertEquals(full, {connectionKey: "PG_Guest", operation: "select", query: "SELECT 1", params: {"a": 1}});

    DbRequest noParams = check requestOf({"connectionKey": "PG_Guest", "operation": "INSERT", "params": ()});
    test:assertEquals(noParams.params, {});
    test:assertEquals(noParams.operation, "insert");

    // Not an object: read as an empty request, which then fails the connection key check.
    test:assertEquals(check requestOf([1, 2]), {connectionKey: "", operation: "", query: "", params: {}});
}

@test:Config {}
function paramsMustBeAnObject() {
    DbRequest|Refusal result = requestOf({"connectionKey": "PG_Guest", "operation": "select", "params": [1]});
    test:assertTrue(result is Refusal);
    if result is Refusal {
        test:assertEquals(result.detail().status, 400);
        test:assertEquals(result.detail().errorType, "BAD_REQUEST");
    }
}

@test:Config {}
function unknownConnectionKeyIsUnauthorized() {
    Refusal? result = checked({connectionKey: "PG_Other", operation: "select", query: "", params: {}});
    test:assertTrue(result is Refusal);
    if result is Refusal {
        test:assertEquals(result.detail().status, 401);
        test:assertEquals(result.detail().errorType, "UNAUTHORIZED");
        test:assertEquals(result.message(), "Invalid operation or not implemented: select");
    }
    Refusal? none = checked({connectionKey: "", operation: "", query: "", params: {}});
    test:assertEquals(none is Refusal ? none.message() : "", "Invalid operation or not implemented: ");
}

@test:Config {}
function unknownOperationIsInvalidRequest() {
    Refusal? result = checked({connectionKey: "PG_ShipTracking", operation: "delete", query: "", params: {}});
    test:assertTrue(result is Refusal);
    if result is Refusal {
        test:assertEquals(result.detail().status, 400);
        test:assertEquals(result.detail().errorType, "INVALID_REQUEST");
        test:assertEquals(result.message(), "Invalid operation or not implemented: delete");
    }
    foreach string operation in ["select", "insert", "update"] {
        test:assertTrue(checked({connectionKey: "PG_Guest", operation, query: "", params: {}}) is ());
        test:assertTrue(checked({connectionKey: "PG_ShipTracking", operation, query: "", params: {}}) is ());
    }
}

@test:Config {}
function settingsWithoutAValueAreNamed() {
    test:assertEquals(settingsNotSet(KEY_GUEST, {}, {}),
            ["database.host", "database.name", "guest.username", "guest.password"]);
    test:assertEquals(settingsNotSet(KEY_SHIP_TRACKING, {host: "db", name: "main"}, {username: "u"}),
            ["shipTracking.password"]);
    test:assertEquals(settingsNotSet(KEY_GUEST, {host: "db", name: "main"}, {username: "u", password: "p"}), []);
    test:assertEquals(settingsNotSet(KEY_GUEST, {host: "  ", name: "main"}, {username: " ", password: "p"}),
            ["database.host", "guest.username"]);
}
