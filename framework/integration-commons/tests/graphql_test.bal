import ballerina/test;

// Cases taken from the GraphQL documents seen in the Mule projects and their docs.

@test:Config {}
function operationTypeFollowsTheFirstWord() {
    test:assertEquals(operationTypeOf("mutation ReservationCreate { reservationCreate { key } }"), MUTATION);
    test:assertEquals(operationTypeOf("  subscription S { x }"), SUBSCRIPTION);
    test:assertEquals(operationTypeOf("query AvailableVoyages { availableVoyages { pkg { key } } }"), QUERY);
    test:assertEquals(operationTypeOf("{ cities { key } }"), QUERY);
}

@test:Config {}
function operationNameIsTheWordAfterTheType() {
    test:assertEquals(operationNameOf("query AvailableVoyages { availableVoyages { x } }"), "AvailableVoyages");
    test:assertEquals(operationNameOf("mutation transactionCreate($a: X) { transactionCreate { key } }"),
            "transactionCreate");
    test:assertEquals(operationNameOf("{ cities { key } }"), "Anonymous");
    test:assertEquals(operationNameOf(""), "Anonymous");
}

@test:Config {}
function rootFieldIsTheFirstDirectField() {
    test:assertEquals(rootFieldOf("query AvailableVoyages { availableVoyages(params: {}) { pkg { key } } }"),
            "availableVoyages");
    test:assertEquals(rootFieldOf("query Q {\n  cities { key }\n}"), "cities");
    test:assertEquals(rootFieldOf("{ login @include(if: true) { token } }"), "login");
}

@test:Config {}
function aliasIsSkipped() {
    test:assertEquals(rootFieldOf("query Q { mine: reservation(key: \"1\") { key } }"), "reservation");
}

@test:Config {}
function commentsAreIgnored() {
    test:assertEquals(rootFieldOf("# reservations { x }\nquery Q {\n # not this\n reservationCreate { key } }"),
            "reservationCreate");
}

@test:Config {}
function inlineFragmentRootField() {
    test:assertEquals(rootFieldOf("query Q { ... on Query { availableShorex { key } } }"), "availableShorex");
}

@test:Config {}
function fragmentSpreadResolvesToTheFragmentsFirstField() {
    string gql = "query Q { ...Voyages } fragment Voyages on Query { availableVoyages { pkg { key } } }";
    test:assertEquals(rootFieldOf(gql), "availableVoyages");
}

@test:Config {}
function noRootFieldGivesNil() {
    test:assertEquals(rootFieldOf(""), ());
    test:assertEquals(rootFieldOf("query Q"), ());
    test:assertEquals(rootFieldOf("query Q { ...Missing }"), ());
}
