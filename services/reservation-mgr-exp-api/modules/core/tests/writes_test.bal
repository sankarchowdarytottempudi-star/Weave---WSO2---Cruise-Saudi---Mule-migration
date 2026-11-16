import ballerina/test;

@test:Config {}
function writeIsRecognised() {
    test:assertTrue(isWrite("mutation { reservationStore { resId } }"));
    test:assertTrue(isWrite("  mutation Store($a: Int) { reservationStore(a: $a) { resId } }"));
    test:assertTrue(isWrite("# saved from the booking page\nmutation { reservationStore { resId } }"));
}

@test:Config {}
function readIsNotAWrite() {
    test:assertFalse(isWrite("query AvailableVoyages { availableVoyages { pkg { key } } }"));
    test:assertFalse(isWrite("{ reservation { resId } }"));
    test:assertFalse(isWrite("query { mutationLog { id } }"));
    test:assertFalse(isWrite(""));
}
