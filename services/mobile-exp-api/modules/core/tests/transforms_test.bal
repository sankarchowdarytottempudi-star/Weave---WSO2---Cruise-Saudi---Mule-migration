import ballerina/test;

// Replace with the source's real cases (captured requests and responses).
@test:Config {}
function mobileExpApiMainLoginHeadersFirstNameKeepsInputUntilMigrated() {
    test:assertEquals(mobileExpApiMainLoginHeadersFirstName({a: 1}), {a: 1});
}
