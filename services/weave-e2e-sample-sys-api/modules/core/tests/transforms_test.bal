import ballerina/test;

// Replace with the source's real cases (captured requests and responses).
@test:Config {}
function getItemsItemIdSampleApiConfigTransformSetPayloadKeepsInputUntilMigrated() {
    test:assertEquals(getItemsItemIdSampleApiConfigTransformSetPayload({a: 1}), {a: 1});
}
