import ballerina/test;

final TelrStore & readonly STORE = {
    storeId: "100",
    authKey: "test-key",
    orderTest: "1",
    returnAuthorised: "https://example.test/ok",
    returnDeclined: "https://example.test/declined",
    returnCancelled: "https://example.test/cancelled"
};

@test:Config {}
function sessionRequestCarriesStoreAndOrder() returns error? {
    json body = {
        "order": {cartid: "RES123-1", amount: "150.50", currency: "SAR", description: "Booking", trantype: "sale"},
        customer: {
            ref: "A|B|77",
            email: "guest@example.test",
            name: {title: "Mr", forenames: "A", surname: "B"},
            address: {line1: "1 Street", city: "Jeddah", country: "SA"},
            phone: "0500000000"
        },
        extra: {extra2: "[{\"paymentCode\":\"X\",\"amount\":10}]"}
    };
    map<json> telr = check sessionRequestOf(body, STORE);
    test:assertEquals(telr["method"], "create");
    test:assertEquals(telr["store"], "100");
    test:assertEquals(telr["authkey"], "test-key");
    test:assertEquals(telr["framed"], "0");
    test:assertEquals(telr["order"], {cartid: "RES123-1", test: "1", amount: "150.50", currency: "SAR",
        description: "Booking", trantype: "sale"});
    test:assertEquals(telr["return"], {authorised: "https://example.test/ok",
        declined: "https://example.test/declined", cancelled: "https://example.test/cancelled"});
    test:assertEquals(fieldOf(telr, "customer", "name", "surname"), "B");
    test:assertEquals(fieldOf(telr, "customer", "address", "city"), "Jeddah");
    test:assertEquals(fieldOf(telr, "customer", "address", "line2"), ());
    test:assertEquals(fieldOf(telr, "extra", "extra2"), "[{\"paymentCode\":\"X\",\"amount\":10}]");
    test:assertEquals(fieldOf(telr, "extra", "extra1"), ());
}

@test:Config {}
function missingFieldsAreSentAsNull() returns error? {
    map<json> telr = check sessionRequestOf({"order": {cartid: "RES9-1"}}, STORE);
    string text = telr.toJsonString();
    test:assertTrue(text.includes("\"amount\":null"));
    test:assertTrue(text.includes("\"phone\":null"));
    test:assertTrue(text.includes("\"extra3\":null"));
}

@test:Config {}
function wrappedSessionBodyIsAccepted() returns error? {
    json body = {session: {locale: "en", "order": {cartid: "RES5-2", amount: 10, currency: "SAR"}, customer: {ref: "c"}}};
    map<json> telr = check sessionRequestOf(body, STORE);
    test:assertEquals(fieldOf(telr, "order", "cartid"), "RES5-2");
    test:assertEquals(fieldOf(telr, "order", "amount"), 10);
    test:assertEquals(fieldOf(telr, "customer", "ref"), "c");
}

@test:Config {}
function sessionWithoutOrderIsRefused() {
    test:assertTrue(sessionRequestOf({customer: {ref: "c"}}, STORE) is error);
    test:assertTrue(sessionRequestOf("text", STORE) is error);
    test:assertTrue(sessionRequestOf({session: {customer: {}}}, STORE) is error);
}

@test:Config {}
function statusRequestCarriesOrderRef() returns error? {
    map<json> telr = check statusRequestOf({orderRef: "ABC123"}, STORE);
    test:assertEquals(telr, {method: "check", store: "100", authkey: "test-key", "order": {ref: "ABC123"}});
}

@test:Config {}
function statusWithoutOrderRefIsRefused() {
    test:assertTrue(statusRequestOf({}, STORE) is error);
    test:assertTrue(statusRequestOf({orderRef: "  "}, STORE) is error);
    test:assertTrue(statusRequestOf([], STORE) is error);
}

@test:Config {}
function placeholderAddresses() {
    test:assertTrue(isPlaceholderAddress(""));
    test:assertTrue(isPlaceholderAddress("http://localhost"));
    test:assertTrue(isPlaceholderAddress("https://LOCALHOST:8443/x"));
    test:assertTrue(isPlaceholderAddress("http://127.0.0.1:9000"));
    test:assertFalse(isPlaceholderAddress("https://gateway.example.test"));
}
