import ballerina/test;

// Made-up audit rows; no real booking, order or session appears here.

final readonly & map<json> ROW = {
    session_id: "sess-1",
    request_payload: "{\"order\":{\"cartId\":\"B100\"}}",
    response_payload: "{\"order\":{\"ref\":\"REF-1\"}}",
    attempt_http_status: (),
    attempt_error_code: (),
    attempt_status: (),
    attempt_remarks: ()
};

function rowWith(map<json> changes) returns map<json> {
    map<json> row = {};
    foreach [string, json] [key, value] in ROW.entries() {
        row[key] = value;
    }
    foreach [string, json] [key, value] in changes.entries() {
        row[key] = value;
    }
    return row;
}

// ---- settings ------------------------------------------------------------------------------

@test:Config {}
function placeholderAddressesAreNotSet() {
    test:assertTrue(isPlaceholderAddress(""));
    test:assertTrue(isPlaceholderAddress("http://localhost"));
    test:assertTrue(isPlaceholderAddress("http://LOCALHOST:9090"));
    test:assertTrue(isPlaceholderAddress("http://127.0.0.1:80"));
    test:assertFalse(isPlaceholderAddress("http://financial-transactions-proc-api.wso2.svc:80"));
}

final readonly & StartCheck COMPLETE = {
    frequencyMinutes: 2,
    sql: "select 1",
    connectionKey: "KEY",
    dbUrl: "https://db.example",
    paymentsUrl: "http://payments.example",
    emailEnabled: false,
    emailUrl: "http://localhost",
    emailTo: ""
};

@test:Config {}
function timerMayStartWhenEverythingNeededIsSet() {
    test:assertEquals(settingsNotSet(COMPLETE), []);
}

@test:Config {}
function timerDoesNotNeedTheEmailBackendWhileEmailIsOff() {
    test:assertEquals(settingsNotSet({
        frequencyMinutes: 2,
        sql: "select 1",
        connectionKey: "KEY",
        dbUrl: "https://db.example",
        paymentsUrl: "http://payments.example",
        emailEnabled: false,
        emailUrl: "",
        emailTo: ""
    }), []);
}

@test:Config {}
function timerNamesEverySettingThatIsMissing() {
    test:assertEquals(settingsNotSet({
        frequencyMinutes: 0,
        sql: " ",
        connectionKey: "",
        dbUrl: "http://localhost",
        paymentsUrl: "",
        emailEnabled: true,
        emailUrl: "http://localhost",
        emailTo: ""
    }), ["scheduler.frequencyMinutes", "query.sql", "dbSysApi.connectionKey", "dBSysAPIHTTPRequestConfig.url",
        "financialTransactionsHTTPRequestConfig.url", "emailSysAPIHTTPRequestConfig.url", "email.to"]);
}

// ---- text helpers --------------------------------------------------------------------------

@test:Config {}
function replaceTextReplacesEveryOccurrence() {
    test:assertEquals(replaceText("a_b_c", "_", ""), "abc");
    test:assertEquals(replaceText("x :n y :n", ":n", "15"), "x 15 y 15");
    test:assertEquals(replaceText("nothing", ":n", "1"), "nothing");
    test:assertEquals(replaceText("abc", "", "1"), "abc");
}

@test:Config {}
function splitTextKeepsPartsAsTheyAre() {
    test:assertEquals(splitText("a@x.test, b@x.test", ","), ["a@x.test", " b@x.test"]);
    test:assertEquals(splitText("one", ","), ["one"]);
}

@test:Config {}
function normalizedKeyIgnoresCaseBlanksAndUnderscores() {
    test:assertEquals(normalizedKey(" Attempt_HTTP_Status "), "attempthttpstatus");
    test:assertEquals(normalizedKey(()), "");
    test:assertEquals(normalizedKey(12), "12");
}

// ---- the request to the database system API ------------------------------------------------

@test:Config {}
function dbRequestPutsTheThreeNumbersIntoTheStatement() {
    QuerySettings query = {
        sql: "select * from t where a > :lookbackMinutes and b > :graceMinutes limit :batchSize",
        lookbackMinutes: 15,
        graceMinutes: 0,
        batchSize: 150
    };
    test:assertEquals(dbSelectRequest(query, "KEY", "sess"), {
        connectionKey: "KEY",
        operation: "Select",
        query: "select * from t where a > 15 and b > 0 limit 150",
        params: {sessionId: "sess"}
    });
}

@test:Config {}
function dbRequestKeepsAStatementWithoutPlaceholders() {
    test:assertEquals(dbSelectRequest({sql: "select 1"}, "K", "").get("query"), "select 1");
}

// ---- the rows of the reply -----------------------------------------------------------------

@test:Config {}
function rowsAreTakenFromDataRecordsResultOrRows() {
    json[] rows = [{a: 1}];
    test:assertEquals(recordsOf({data: rows}), rows);
    test:assertEquals(recordsOf({records: rows}), rows);
    test:assertEquals(recordsOf({result: rows}), rows);
    test:assertEquals(recordsOf({rows: rows}), rows);
    test:assertEquals(recordsOf({data: (), rows: rows}), rows);
    test:assertEquals(recordsOf({data: [], rows: rows}), []);
}

@test:Config {}
function aPlainListIsTheRows() {
    json[] rows = [{session_id: "s"}, {session_id: "t"}];
    test:assertEquals(recordsOf(rows), rows);
    test:assertEquals(rowsOf(recordsOf(rows)).length(), 2);
}

@test:Config {}
function aReplyWithoutAListHasNoRows() {
    test:assertEquals(rowsOf(recordsOf({message: "no rows"})), []);
    test:assertEquals(rowsOf(recordsOf(())), []);
    test:assertEquals(rowsOf(recordsOf("text")), []);
}

// ---- reading a row -------------------------------------------------------------------------

@test:Config {}
function paymentIsReadFromAnObjectRow() {
    PaymentRequest|error request = paymentRequestOf(ROW);
    test:assertEquals(request, {orderRef: "REF-1", bookingNumber: "B100", sessionId: "sess-1"});
}

@test:Config {}
function columnNamesMayBeUpperOrCamelCase() {
    json upper = {
        SESSION_ID: "s",
        REQUEST_PAYLOAD: "{\"order\":{\"cartid\":\"B2\"}}",
        RESPONSE_PAYLOAD: "{\"order\":{\"ref\":\"R2\"}}"
    };
    test:assertEquals(paymentRequestOf(upper), {orderRef: "R2", bookingNumber: "B2", sessionId: "s"});
    json camel = {sessionId: "s3", requestPayload: {"order": {cartId: "B3"}}, responsePayload: {"order": {ref: "R3"}}};
    test:assertEquals(paymentRequestOf(camel), {orderRef: "R3", bookingNumber: "B3", sessionId: "s3"});
}

@test:Config {}
function cartIdWinsOverCartid() {
    json row = {request_payload: {"order": {cartId: "UPPER", cartid: "lower"}}, response_payload: {"order": {ref: "R"}}};
    PaymentRequest|error request = paymentRequestOf(row);
    test:assertTrue(request is PaymentRequest && request.bookingNumber == "UPPER");
}

@test:Config {}
function wrappedValuesAreUnwrapped() {
    json row = {
        session_id: {value: "s4"},
        request_payload: {value: "{\"order\":{\"cartId\":\"B4\"}}", 'type: "json"},
        response_payload: {value: "{\"order\":{\"ref\":\"R4\"}}"}
    };
    test:assertEquals(paymentRequestOf(row), {orderRef: "R4", bookingNumber: "B4", sessionId: "s4"});
}

@test:Config {}
function aListRowUsesNamedItemsFirst() {
    json row = [
        {name: "SESSION_ID", value: "s5"},
        {column: "request_payload", VALUE: "{\"order\":{\"cartId\":\"B5\"}}"},
        {columnName: "responsePayload", data: "{\"order\":{\"ref\":\"R5\"}}"}
    ];
    test:assertEquals(paymentRequestOf(row), {orderRef: "R5", bookingNumber: "B5", sessionId: "s5"});
}

@test:Config {}
function aListRowFallsBackToPositionsTenAndThirteen() {
    json[] row = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, "{\"order\":{\"cartId\":\"B6\"}}", 11, 12, "{\"order\":{\"ref\":\"R6\"}}"];
    test:assertEquals(paymentRequestOf(row), {orderRef: "R6", bookingNumber: "B6", sessionId: ()});
    json[] short = [0, 1];
    test:assertEquals(paymentRequestOf(short), {orderRef: (), bookingNumber: (), sessionId: ()});
}

@test:Config {}
function aRowWithoutPayloadsGivesNothing() {
    PaymentRequest|error request = paymentRequestOf({session_id: "s7", request_payload: " ", response_payload: ()});
    test:assertEquals(request, {orderRef: (), bookingNumber: (), sessionId: "s7"});
    test:assertTrue(request is PaymentRequest && !isComplete(request));
}

@test:Config {}
function aPayloadThatIsNotJsonIsAnError() {
    test:assertTrue(paymentRequestOf(rowWith({request_payload: "{not json"})) is error);
    test:assertTrue(paymentRequestOf(rowWith({response_payload: "<html>"})) is error);
}

@test:Config {}
function completeNeedsBothOrderRefAndBookingNumber() {
    test:assertTrue(isComplete({orderRef: "R", bookingNumber: "B", sessionId: ()}));
    test:assertTrue(isComplete({orderRef: "R", bookingNumber: 12345, sessionId: ()}));
    test:assertFalse(isComplete({orderRef: "", bookingNumber: "B", sessionId: "s"}));
    test:assertFalse(isComplete({orderRef: "R", bookingNumber: (), sessionId: "s"}));
}

@test:Config {}
function requestBodyHasOrderRefAndBookingNumberOnly() {
    test:assertEquals(requestBodyOf({orderRef: "R", bookingNumber: "B", sessionId: "s"}), {orderRef: "R", bookingNumber: "B"});
}

@test:Config {}
function emptinessFollowsTheOldRule() {
    test:assertTrue(isEmptyValue(()));
    test:assertTrue(isEmptyValue(""));
    test:assertTrue(isEmptyValue([]));
    test:assertTrue(isEmptyValue({}));
    test:assertFalse(isEmptyValue(" "));
    test:assertFalse(isEmptyValue(0));
    test:assertFalse(isEmptyValue({a: 1}));
}

// ---- the retry decision --------------------------------------------------------------------

@test:Config {}
function noEarlierAttemptIsProcessed() {
    RetryDecision decision = retryDecisionOf(ROW);
    test:assertTrue(decision.shouldProcess);
    test:assertEquals(decision.reason, "No previous payment attempt found");
    test:assertEquals(decision.httpStatus, "");
}

@test:Config {}
function http500IsProcessedAgain() {
    RetryDecision decision = retryDecisionOf(rowWith({attempt_http_status: 500, attempt_error_code: "anything"}));
    test:assertTrue(decision.shouldProcess);
    test:assertEquals(decision.reason, "Latest payment attempt was HTTP 500");
    test:assertEquals(decision.errorCode, "ANYTHING");
}

@test:Config {}
function telrPendingIsProcessedAgain() {
    RetryDecision decision = retryDecisionOf(rowWith({attempt_http_status: "400", attempt_error_code: "telr_pending"}));
    test:assertTrue(decision.shouldProcess);
    test:assertEquals(decision.reason, "Latest payment attempt was TELR_PENDING");
}

@test:Config {}
function customErrorIsProcessedAgain() {
    RetryDecision decision = retryDecisionOf({ATTEMPT_HTTP_STATUS: 400, AttemptErrorCode: "Custom-Error"});
    test:assertTrue(decision.shouldProcess);
    test:assertEquals(decision.reason, "Latest payment attempt was CUSTOM-ERROR");
}

// As in the old script: of two columns with the same name in different spellings, the first one counts.
@test:Config {}
function theFirstColumnOfANameCounts() {
    RetryDecision decision = retryDecisionOf({attempt_http_status: (), ATTEMPT_HTTP_STATUS: 200});
    test:assertEquals(decision.httpStatus, "");
    test:assertTrue(decision.shouldProcess);
}

@test:Config {}
function otherAnswersAreFinal() {
    foreach [json, json] [status, code] in [[400, "VALIDATION"], [200, ()], [404, "TELR_PENDING"], ["502", ""]] {
        RetryDecision decision = retryDecisionOf(rowWith({attempt_http_status: status, attempt_error_code: code}));
        test:assertFalse(decision.shouldProcess);
        test:assertEquals(decision.reason, "Latest payment attempt is terminal or not retryable");
    }
}

@test:Config {}
function decisionCarriesStatusAndRemarks() {
    RetryDecision decision = retryDecisionOf(rowWith({
        attempt_http_status: {value: 200},
        attempt_status: "SUCCESS",
        attempt_remarks: "done"
    }));
    test:assertEquals(decision.httpStatus, "200");
    test:assertEquals(decision.status, "SUCCESS");
    test:assertEquals(decision.remarks, "done");
}

@test:Config {}
function aListRowHasNoAttemptColumnsSoItIsProcessed() {
    test:assertTrue(retryDecisionOf([1, 2, 3]).shouldProcess);
}

// ---- the lines of the summary --------------------------------------------------------------

final readonly & PaymentRequest PAYMENT = {orderRef: "REF-1", bookingNumber: "B100", sessionId: "sess-1"};

@test:Config {}
function successLineKeepsStatusAndAnswer() {
    test:assertEquals(successRecord(PAYMENT, "c-1", 200, {ok: true}), {
        sessionId: "sess-1",
        correlationId: "c-1",
        orderRef: "REF-1",
        bookingNumber: "B100",
        statusCode: 200,
        response: {ok: true}
    });
    test:assertEquals(successRecord(PAYMENT, "c-1", 204, ()).get("response"), {});
}

@test:Config {}
function notRetryableLineSaysWhy() {
    RetryDecision decision = retryDecisionOf(rowWith({
        attempt_http_status: 400,
        attempt_error_code: "validation",
        attempt_status: "FAILED",
        attempt_remarks: "card declined"
    }));
    test:assertEquals(notRetryableRecord(PAYMENT, "c-2", decision), {
        sessionId: "sess-1",
        correlationId: "c-2",
        orderRef: "REF-1",
        bookingNumber: "B100",
        reason: "Latest payment attempt is terminal or not retryable: httpStatus=400, errorCode=VALIDATION, status=FAILED",
        response: "card declined"
    });
}

@test:Config {}
function missingLineHasEmptyTextForWhatIsMissing() {
    test:assertEquals(missingRecord({orderRef: (), bookingNumber: "B9", sessionId: ()}, "c-3"), {
        sessionId: "",
        correlationId: "c-3",
        orderRef: "",
        bookingNumber: "B9",
        reason: "Missing orderRef or bookingNumber"
    });
}

@test:Config {}
function failedLineKeepsStatusAndAnswer() {
    test:assertEquals(failedRecord(PAYMENT, "c-4", "HTTP:INTERNAL_SERVER_ERROR", 500, "it failed", {message: "x"}), {
        sessionId: "sess-1",
        correlationId: "c-4",
        orderRef: "REF-1",
        bookingNumber: "B100",
        errorType: "HTTP:INTERNAL_SERVER_ERROR",
        statusCode: 500,
        description: "it failed",
        response: {message: "x"}
    });
}

@test:Config {}
function failedLineOfAnUnreadableRowIsEmptyButNamed() {
    test:assertEquals(failedRecord((), "c-5", "MULE:EXPRESSION", "", "not JSON", ()), {
        sessionId: "",
        correlationId: "c-5",
        orderRef: "",
        bookingNumber: "",
        errorType: "MULE:EXPRESSION",
        statusCode: "",
        description: "not JSON",
        response: {}
    });
}

@test:Config {}
function rowKeysAreNamesOnly() {
    test:assertEquals(rowKeysOf({a: "secret", b: 2}), ["a", "b"]);
    test:assertEquals(rowKeysOf([1, 2]), []);
}

@test:Config {}
function failuresAreNamedAsBefore() {
    test:assertEquals(errorTypeOfStatus(400), "HTTP:BAD_REQUEST");
    test:assertEquals(errorTypeOfStatus(500), "HTTP:INTERNAL_SERVER_ERROR");
    test:assertEquals(errorTypeOfStatus(503), "HTTP:SERVICE_UNAVAILABLE");
    test:assertEquals(errorTypeOfStatus(504), "HTTP:TIMEOUT");
    test:assertEquals(errorTypeOfStatus(302), "HTTP:RESPONSE_VALIDATION");
}

@test:Config {}
function failureTextNamesThePathNotTheHost() {
    test:assertEquals(failureDescription("/p/v1/x", 500), "HTTP POST on resource '/p/v1/x' failed: status code 500.");
    test:assertEquals(failureDescription("/p/v1/x", ()), "HTTP POST on resource '/p/v1/x' failed: the backend could not be reached.");
    test:assertEquals(failureDescription("/p/v1/x", (), true), "HTTP POST on resource '/p/v1/x' failed: the answer did not come in time.");
}
