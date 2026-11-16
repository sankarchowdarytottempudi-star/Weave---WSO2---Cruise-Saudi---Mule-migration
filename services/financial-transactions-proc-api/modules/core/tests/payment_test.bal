import ballerina/test;

// Made-up values only: no real booking, order, customer or account appears in these tests.

isolated function telrPaid(string amount = "500.00", string status = "Paid") returns json => {
    "method": "check",
    "order": {
        "ref": "TESTREF0001",
        "cartid": "RES900001-1700000000",
        "amount": amount,
        "currency": "SAR",
        "status": {"code": 3, "text": status},
        "customer": {"ref": "web|900777", "email": "guest@example.test"}
    }
};

isolated function searchAnswer(json[] transactions = []) returns json => {
    "data": {
        "reservationsSearch": {
            "edges": [
                {
                    "cursor": "c1",
                    "node": {
                        "reservation": {
                            "key": "900001",
                            "invoiceTotals": {"invoiceTotal": 2000, "grossDue": 1500.5},
                            "transactions": transactions,
                            "paymentSchedule": [
                                {"dueType": "FIRST DEPOSIT", "amount": 300, "paid": false},
                                {"dueType": "ADDON", "amount": 150, "paid": false},
                                {"dueType": "SHOREX", "amount": 50, "paid": false},
                                {"dueType": "FINAL PAYMENT", "amount": 1000, "paid": false},
                                {"dueType": "FINAL PAYMENT", "amount": 500.5, "paid": false}
                            ]
                        }
                    }
                }
            ]
        }
    }
};

@test:Config {}
function inputIsChecked() {
    PaymentInput|error ok = paymentInputOf({"orderRef": " TESTREF0001 ", "bookingNumber": "RES900001-1"});
    test:assertTrue(ok is PaymentInput);
    if ok is PaymentInput {
        test:assertEquals(ok.orderRef, "TESTREF0001");
        test:assertEquals(ok.bookingNumber, "RES900001-1");
    }
    test:assertTrue(paymentInputOf({"bookingNumber": "900001"}) is error);
    test:assertTrue(paymentInputOf({"orderRef": "A", "bookingNumber": ""}) is error);
    test:assertTrue(paymentInputOf({"orderRef": "A' OR 1=1", "bookingNumber": "900001"}) is error);
    test:assertTrue(paymentInputOf({"orderRef": "A", "bookingNumber": "9\" }) { x"}) is error);
    test:assertTrue(paymentInputOf("text") is error);
}

@test:Config {}
function bookingKeyFollowsTheMuleRule() {
    test:assertEquals(bookingKeyOf("RES900001-1700000000"), "900001");
    test:assertEquals(bookingKeyOf("900001"), "900001");
    test:assertEquals(bookingKeyOf("900001-2"), "900001");
    test:assertTrue(bookingMatches(telrPaid(), "900001"));
    test:assertTrue(bookingMatches(telrPaid(), "RES900001-77"));
    test:assertFalse(bookingMatches(telrPaid(), "900002"));
    test:assertFalse(bookingMatches({"error": {"message": "no such order"}}, "900001"));
}

@test:Config {}
function expectedAmountsComeFromTheFirstReservation() {
    decimal[] amounts = expectedAmountsOf(reservationsOf(searchAnswer()));
    test:assertEquals(amounts, [500d, 1500.5d, 2000d, 1500.5d]);
    test:assertEquals(expectedAmountsOf([]), []);
}

@test:Config {}
function validationGivesTheMuleAnswers() {
    test:assertEquals(validationOf(telrPaid(), "900001", searchAnswer()), "Success");
    test:assertEquals(validationOf(telrPaid("2000"), "RES900001-5", searchAnswer()), "Success");
    test:assertEquals(validationOf(telrPaid("1500.50"), "900001", searchAnswer()), "Success");
    test:assertEquals(validationOf(telrPaid(), "900002", searchAnswer()),
            "Booking number validation failed. The booking number 900002 does not match the Telr payment details.");
    test:assertEquals(validationOf(telrPaid(status = "Pending"), "900001", ()),
            "Payment is not successful. Current status is Pending.");
    test:assertEquals(validationOf(telrPaid("123.45"), "900001", searchAnswer()),
            "Payment amount 123.45 does not match any expected booking amount in the system.");
    test:assertEquals(validationOf(telrPaid(), "900001", searchAnswer([{"externalIdent": "TESTREF0001"}])),
            "Order reference TESTREF0001 has already been processed and cannot be processed again.");
    // Nothing found in Seaware: no amount can match.
    test:assertEquals(validationOf(telrPaid(), "900001", {"data": {"reservationsSearch": {"edges": []}}}),
            "Payment amount 500.00 does not match any expected booking amount in the system.");
}

@test:Config {}
function seawareRequestsCarryOnlyTheReservationNumber() {
    test:assertTrue(searchRequestOf("RES900001-9").get("query").toString().includes("keys: \"900001\""));
    test:assertEquals(searchRequestOf("900001").get("variables"), {});
    test:assertTrue(lockRequestOf("RES900001-9").get("query").toString()
            .includes("reservationLock(input: { key: \"900001\",duration: \"PT15M\" })"));
    test:assertTrue(storeRequestOf("900001").get("query").toString()
            .includes("reservationStore(input: { id: \"Reservation|900001\", unlock: true })"));
    string login = loginRequestOf({userName: "agent\"x", password: "p\\w"}).get("query").toString();
    test:assertTrue(login.includes("login: \"agent\\\"x\", password: \"p\\\\w\""));
}

@test:Config {}
function transactionCreateIsBuiltLikeMule() returns error? {
    map<json> request = check transactionCreateRequestOf(telrPaid(), [], "AROYA_TEST");
    string query = request.get("query").toString();
    test:assertTrue(query.startsWith("mutation TransactionCreate { transactionCreate( input: { payments: { payments: [{ amount: 500.00,"));
    test:assertTrue(query.includes("currency: {key: \"SAR\"}"));
    test:assertTrue(query.includes("formOfTransaction: {key: \"Credit Card\"}"));
    test:assertTrue(query.includes("creditCardMerchant: \"AROYA_TEST\""));
    test:assertTrue(query.includes("creditCardServerType: \"TELR\""));
    test:assertTrue(query.includes("externalIdent: \"TESTREF0001\""));
    test:assertTrue(query.includes("sourceEntity: {key: \"900777\",type: Client}"));
    test:assertTrue(query.includes("destinationEntity: {key: \"900001\",type: Reservation}"));
    test:assertTrue(query.includes("creditCardServerResponse: \"{\\\"method\\\":\\\"check\\\",\\\"order\\\":{\\\"ref\\\":\\\"TESTREF0001\\\""));
    test:assertFalse(query.includes("componentDistr"));
    test:assertTrue(query.endsWith("] } } ) { operationResult } }"));

    // The split as it arrives: parsed from the JSON text saved with the payment session.
    json[] split = extra2Of([{"payload": "{\"extra\":{\"extra2\":[{\"paymentCode\":\"ADDON1\",\"amount\":150},"
            + "{\"paymentCode\":\"SHX\",\"amount\":\"50.5\"}]}}"}]);
    map<json> withSplit = check transactionCreateRequestOf(telrPaid(), split, "AROYA_PROD");
    test:assertTrue(withSplit.get("query").toString().includes(
            ", componentDistr: [{paymentCode: \"ADDON1\", amount: 150}, {paymentCode: \"SHX\", amount: 50.5}]"));

    test:assertTrue(transactionCreateRequestOf(telrPaid("abc"), [], "AROYA_TEST") is error);
    test:assertTrue(transactionCreateRequestOf(telrPaid(), [{"paymentCode": "X", "amount": "1) } evil"}], "AROYA_TEST") is error);
    test:assertTrue(transactionCreateRequestOf({"order": {"ref": "R", "cartid": "RES1-1", "amount": "1", "currency": "SAR"}},
            [], "AROYA_TEST") is error);
}

@test:Config {}
function compactJsonHasNoSpaces() {
    test:assertEquals(compactJson({"a": 1, "b": [true, (), "x y"], "c": {"d": "q\"r"}}),
            "{\"a\":1,\"b\":[true,null,\"x y\"],\"c\":{\"d\":\"q\\\"r\"}}");
}

@test:Config {}
function splitIsReadFromEveryStoredShape() {
    json session = {"order": {"cartid": "RES900001-1"}, "extra": {"extra2": [{"paymentCode": "A", "amount": 1}]}};
    json[] expected = [{"paymentCode": "A", "amount": 1}];
    test:assertEquals(extra2Of([{"payload": session}]), expected);
    test:assertEquals(extra2Of([{"payload": session.toJsonString()}]), expected);
    test:assertEquals(extra2Of({"data": [{"payload": {"type": "jsonb", "value": session.toJsonString()}}]}), expected);
    json textSplit = {"extra": {"extra2": "[{\"paymentCode\":\"A\",\"amount\":1}]"}};
    test:assertEquals(extra2Of([{"payload": textSplit}]), expected);
    test:assertEquals(extra2Of([{"payload": {"session": session}}]), expected);
    test:assertEquals(extra2Of([]), []);
    test:assertEquals(extra2Of([{"payload": ""}]), []);
    test:assertEquals(extra2Of([{"payload": {"extra": {"extra2": ""}}}]), []);
    test:assertEquals(extra2Of("not rows"), []);
}

@test:Config {}
function seawareErrorsAreRecognised() {
    test:assertEquals(firstSeawareError({"data": {}}), ());
    test:assertEquals(firstSeawareError({"errors": []}), ());
    test:assertEquals(firstSeawareError({"errors": [{"message": "Reservation is locked"}]}), "Reservation is locked");
    test:assertTrue(isSessionError("Session context not found or expired for GUID"));
    test:assertTrue(isSessionError("Permission Error: Query is not permitted"));
    test:assertFalse(isSessionError("Reservation is locked"));
    test:assertEquals(loginTokenOf({"data": {"login": {"token": "made-up-token"}}}), "made-up-token");
    test:assertEquals(loginTokenOf({"data": {"login": ()}}), ());
}

@test:Config {}
function reconciliationFollowsTheStoreAnswer() {
    json stored = {"data": {"reservationStore": {"result": {"key": "900001", "transactions": [{"externalIdent": "TESTREF0001"}]}, "errors": []}}};
    test:assertTrue(storedTransactionFound(stored, "TESTREF0001"));
    test:assertFalse(storedTransactionFound(stored, "OTHER"));
    test:assertFalse(storedTransactionFound({"data": {"reservationStore": ()}}, "TESTREF0001"));
    test:assertEquals(reconciliationMessage(stored, "OTHER"),
            "Order reference OTHER not found in Seaware store response. Requires reconciliation.");
    json warned = {"data": {"reservationStore": {"result": (), "errors": [{"message": "Balance mismatch"}]}}};
    test:assertEquals(reconciliationMessage(warned, "OTHER"),
            "Order reference OTHER not found in Seaware store response. Additionally, Seaware returned a warning: Balance mismatch. Requires reconciliation.");
}

@test:Config {}
function errorCodesFollowTheMuleTable() {
    test:assertEquals(errorCodeOf("Order reference X has already been processed and cannot be processed again."), "SW_ALREADY_PROCESSED");
    test:assertEquals(errorCodeOf("Order reference X not found in Seaware store response. Requires reconciliation."), "SW_RECONCILIATION_REQUIRED");
    test:assertEquals(errorCodeOf("Booking number validation failed. The booking number 1 does not match the Telr payment details."), "SW_INVALID_BOOKING_NUMBER");
    test:assertEquals(errorCodeOf("Payment amount 5 does not match any expected booking amount in the system."), "SW_AMOUNT_MISMATCH");
    test:assertEquals(errorCodeOf("Payment is not successful. Current status is Declined."), "TELR_DECLINED");
    test:assertEquals(errorCodeOf("Payment is not successful. Current status is Payment Requested."), "TELR_PAYMENT_REQUESTED");
    test:assertEquals(errorCodeOf("anything else"), "SW_UNKNOWN");
}

@test:Config {}
function databaseRequestsAreBuiltLikeMule() {
    PaymentInput input = {orderRef: "TESTREF0001", bookingNumber: "900001"};
    map<json> ok = auditInsertOf(input, "corr-1", "web", 200, "Payment processed successfully", ());
    test:assertEquals(ok.get("operation"), "insert");
    test:assertEquals(ok.get("connectionKey"), "PG_Guest");
    test:assertEquals(ok.get("query"), "INSERT INTO cs_mule_framework.cs_payment_process_attempt_audit (booking_no, telr_ref_no,"
            + " attempt_correlation_id, source, status, http_status, remarks) VALUES ('900001', 'TESTREF0001', 'corr-1', 'web',"
            + " 'Success', 200, 'Payment processed successfully')");
    map<json> failed = auditInsertOf(input, "corr-1", (), 400, "It's refused", "SW_UNKNOWN");
    test:assertEquals(failed.get("query"), "INSERT INTO cs_mule_framework.cs_payment_process_attempt_audit (booking_no, telr_ref_no,"
            + " attempt_correlation_id, status, http_status, error_code, remarks) VALUES ('900001', 'TESTREF0001', 'corr-1',"
            + " 'Failed', 400, 'SW_UNKNOWN', 'It''s refused')");

    map<json> selectRequest = contextSelectOf("TESTREF0001");
    test:assertEquals(selectRequest.get("params"), {"telr_order_ref": "TESTREF0001"});
    json session = {"order": {"cartid": "RES900001-1"}, "extra": {"extra2": []}};
    map<json> insertRequest = contextInsertOf(session);
    test:assertEquals(insertRequest.get("operation"), "select");
    test:assertEquals(insertRequest.get("params"),
            {"booking_ref": "RES900001-1", "telr_order_ref": (), "payload": "{\"order\":{\"cartid\":\"RES900001-1\"},\"extra\":{\"extra2\":[]}}"});
    test:assertEquals(contextIdOf([{"payment_context_id": 42}]), 42);
    test:assertEquals(contextIdOf({"data": [{"payment_context_id": 43}]}), 43);
    test:assertEquals(contextIdOf([]), ());
    test:assertEquals(contextUpdateOf(42, {"order": {"ref": "TESTREF0001"}}).get("params"),
            {"telr_order_ref": "TESTREF0001", "payment_context_id": 42});
}
