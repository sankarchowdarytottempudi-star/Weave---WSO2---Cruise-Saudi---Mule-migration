import ballerina/test;

// Replace with the source's real cases (captured requests and responses).
@test:Config {}
function destinationExperiencesHandlerSubFlowDestinationExperiencesGeKeepsInputUntilMigrated() {
    test:assertEquals(destinationExperiencesHandlerSubFlowDestinationExperiencesGe({a: 1}), {a: 1});
}
