import ballerina/test;

final map<string> & readonly OPER = {"availableVoyages": "/reservation-common-api", "reservationCreate": "/reservation-common-api"};
final map<string> & readonly STATIC = {
    "cities": "/reservation-common-api",
    "Ships": "/reservation-common-api",
    "availableVoyages": "/should-not-win"
};
final map<string> & readonly TARGETS = {"/reservation-common-api": "/reservation-common-proc-api/v1/integration-tasks"};

// ---------- routing ----------

@test:Config {}
function mappedFieldIsRoutedToCommonProc() {
    Route|RoutingError r = resolveRoute("availableVoyages", OPER, STATIC, TARGETS);
    if r is RoutingError {
        test:assertFail(r.message);
    }
    test:assertEquals(r.path, "/reservation-common-proc-api/v1/integration-tasks");
}

@test:Config {}
function lookupIgnoresCaseAndOperationMappingWins() {
    Route|RoutingError ships = resolveRoute("ships", OPER, STATIC, TARGETS);
    test:assertTrue(ships is Route, "static mapping key 'Ships' matches root field 'ships'");
    Route|RoutingError voyages = resolveRoute("AVAILABLEVOYAGES", OPER, STATIC, TARGETS);
    test:assertTrue(voyages is Route && voyages.targetApi == "/reservation-common-api");
}

@test:Config {}
function unmappedFieldIsNotImplemented() {
    Route|RoutingError r = resolveRoute("flightpromotion", OPER, STATIC, TARGETS);
    if r is Route {
        test:assertFail("flightpromotion is not in the mapping");
    }
    test:assertEquals(r.errorType, "NOT_IMPLEMENTED");
    test:assertEquals(r.message, "INVALID_OPERATION: Fields not found in mappings: flightpromotion");
}

@test:Config {}
function targetOtherThanCommonApiIsNotImplemented() {
    Route|RoutingError r = resolveRoute("cabins", {"cabins": "/reservation-core-api"}, {}, TARGETS);
    test:assertTrue(r is RoutingError && r.message == "The query or mutation is invalid.");
}

@test:Config {}
function missingRootFieldIsAGraphqlError() {
    Route|RoutingError r = resolveRoute((), OPER, STATIC, TARGETS);
    test:assertTrue(r is RoutingError && r.errorType == "GRAPHQL_QUERY");
}

@test:Config {}
function quotedConfigKeysAreNormalized() {
    map<string> fromToml = {"\"availableVoyages\"": "/reservation-common-api", "\"/reservation-common-api\"": "/p", " cities ": "x"};
    map<string> keys = normalizeKeys(fromToml);
    test:assertEquals(keys, {"availableVoyages": "/reservation-common-api", "/reservation-common-api": "/p", "cities": "x"});
    Route|RoutingError r = resolveRoute("availableVoyages", normalizeKeys(fromToml), {}, {"/reservation-common-api": "/p"});
    test:assertTrue(r is Route);
}

@test:Config {}
function asyncFlagIsCaseInsensitive() {
    test:assertTrue(isAsyncRequest("TRUE"));
    test:assertTrue(isAsyncRequest("true"));
    test:assertFalse(isAsyncRequest("yes"));
    test:assertFalse(isAsyncRequest(()));
}

// ---------- db-sys-api bodies ----------

@test:Config {}
function asyncInsertMarksTheRequestInProgress() returns error? {
    json body = asyncInsertBody("PG_Guest", "cs_mule_framework.cs_async_req_status", "c-1", "reservation-mgr-exp-api",
            {query: "query Q { cities { key } }"});
    test:assertEquals(check body.operation, "insert");
    test:assertEquals(check body.params.status, "In-Progress");
    test:assertEquals(check body.params.uuid, "c-1");
    string query = check body.query;
    test:assertTrue(query.includes("ON CONFLICT (async_id)"));
}

@test:Config {}
function asyncUpdateCarriesTheOutcome() returns error? {
    json body = asyncUpdateBody("PG_Guest", "t", "c-1", FAILED, "svc", {'error: "TIMEOUT"});
    test:assertEquals(check body.params.status, "Failed");
    test:assertEquals(check body.params.payload, "{\"error\":\"TIMEOUT\"}");
}

@test:Config {}
function mappingLookupUsesTheMuleColumns() returns error? {
    json body = errorMappingBody("PG_Guest", "SELECT endpoint, error, type, code FROM t", "/x/v1/integration-tasks", 503,
            "CIRCUIT_OPEN");
    test:assertEquals(check body.params, {endpoint: "/x/v1/integration-tasks", code: "503", 'type: "CIRCUIT_OPEN"});
}

@test:Config {}
function exactTypeRowWinsOverTheBlankTypeFallback() {
    json rows = [
        {endpoint: "/e", 'error: "Generic message", 'type: "", code: "503"},
        {endpoint: "/e", 'error: "Blocked while recovering", 'type: "CIRCUIT_OPEN", code: "503"}
    ];
    test:assertEquals(mappedErrorBodyOf(rows, "CIRCUIT_OPEN", 503, "c-1"), {
                                                                               messageType: "CIRCUIT_OPEN",
                                                                               message: "Blocked while recovering",
                                                                               responseCode: 503,
                                                                               correlationId: "c-1",
                                                                               errorDoesNotExist: false
                                                                           });
    json generic = mappedErrorBodyOf(rows, "SERVICE_UNAVAILABLE", 503, "c-2");
    test:assertEquals(generic, {
                                   messageType: "SERVICE_UNAVAILABLE",
                                   message: "Generic message",
                                   responseCode: 503,
                                   correlationId: "c-2",
                                   errorDoesNotExist: false
                               });
}

@test:Config {}
function noUsableRowKeepsTheOriginalError() {
    test:assertEquals(mappedErrorBodyOf([], "TIMEOUT", 504, "c"), ());
    test:assertEquals(mappedErrorBodyOf({data: []}, "TIMEOUT", 504, "c"), ());
    test:assertEquals(mappedErrorBodyOf([{'type: "OTHER", 'error: "x"}], "TIMEOUT", 504, "c"), ());
    test:assertEquals(mappedErrorBodyOf({data: [{'type: (), 'error: "Fallback"}]}, "TIMEOUT", 504, "c"),
            {messageType: "TIMEOUT", message: "Fallback", responseCode: 504, correlationId: "c", errorDoesNotExist: false});
}
