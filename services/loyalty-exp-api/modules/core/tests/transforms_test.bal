import ballerina/test;

// Replace with the source's real cases (captured requests and responses).
@test:Config {}
function loyaltyExpApiFieldMappingKeepsInputUntilMigrated() {
    test:assertEquals(loyaltyExpApiFieldMapping({a: 1}), {a: 1});
}
