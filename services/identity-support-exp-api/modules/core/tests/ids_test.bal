import ballerina/test;

@test:Config {}
function ulidHasTimeThenRandomPart() {
    string id = ulidOf(1469918176385, [26, 25, 27, 4, 24, 24, 15, 15, 23, 6, 9, 16, 5, 15, 10, 27]);
    test:assertEquals(id, "01ARYZ6S41TSV4RRFFQ69G5FAV");
    test:assertEquals(id.length(), 26);
}

@test:Config {}
function ulidOfTimeZero() {
    test:assertEquals(ulidOf(0, []), "00000000000000000000000000");
    test:assertEquals(ulidOf(32, [31]).substring(0, 11), "0000000010Z");
}

@test:Config {}
function ulidsSortByTime() {
    string earlier = ulidOf(1700000000000, [31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31, 31]);
    string later = ulidOf(1700000000001, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
    test:assertTrue(earlier < later);
}

@test:Config {}
function checkDigitFollowsTheMuleRule() {
    test:assertEquals(checkDigitOf("120000000"), 5);
    // reversed 987654321 -> 9, 8*2-9=7, 7, 6*2-9=3, 5, 4*2=8, 3, 2*2=4, 1 = 47 -> 3
    test:assertEquals(checkDigitOf("123456789"), 3);
    test:assertEquals(checkDigitOf(""), 0);
}

@test:Config {}
function loyaltyIdIsTenDigits() {
    test:assertEquals(loyaltyIdOf(0), "1200000005");
    string id = loyaltyIdOf(3456789);
    test:assertEquals(id.length(), 10);
    test:assertTrue(id.startsWith("123456789"));
    test:assertEquals(loyaltyIdOf(42).substring(0, 9), "120000042");
}
