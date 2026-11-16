import ballerina/http;
import ballerina/test;

@test:Config {}
function envEndingsAreIgnored() {
    test:assertEquals(normalisePath("/check-in-proc-api-uat/v1/travel-documents/1"), "/check-in-proc-api/v1/travel-documents/1");
    test:assertEquals(normalisePath("person-profile-proc-api-dev/v1?x=1"), "/person-profile-proc-api/v1?x=1");
    test:assertEquals(normalisePath("/plain/v1"), "/plain/v1");
    test:assertEquals(prefixOf("/check-in-proc-api-uat/v1/"), "/check-in-proc-api/v1");
}

@test:Config {}
function longestPrefixWinsAndIsRewritten() {
    readonly & [string, string][] routes = [["/check-in-proc-api/v1/special", "http://b"], ["/check-in-proc-api/v1", "http://a/x/v1"]];
    test:assertEquals(routeOf(routes, "/check-in-proc-api-uat/v1/travel-documents/7/file?operationName=uploadFile"),
            ["http://a/x/v1", "/travel-documents/7/file?operationName=uploadFile"]);
    test:assertEquals(routeOf(routes, "/check-in-proc-api-test/v1/special/1"), ["http://b", "/1"]);
    test:assertEquals(routeOf(routes, "/check-in-proc-api/v1"), ["http://a/x/v1", "/"]);
    test:assertEquals(routeOf(routes, "/check-in-proc-api-uat/v10/x"), ());
    test:assertEquals(routeOf(routes, "/other-api-uat/v1/x"), ());
}

service /routedTarget on new http:Listener(19461) {
    resource function get [string... path](http:Request req) returns json => {target: "routed", path: string:'join("/", ...path)};
}

service /shared on new http:Listener(19462) {
    resource function get [string... path]() returns json => {target: "shared", path: string:'join("/", ...path)};
}

@test:Config {}
function callsGoToTheRoutedServiceOrTheSharedAddress() returns error? {
    RoutedClient c = check new ({url: "http://127.0.0.1:19462/shared"},
        {"/check-in-proc-api-uat/v1": "http://127.0.0.1:19461/routedTarget/check-in-proc-api/v1", "/empty/v1": ""});
    http:Response r1 = check c->execute("GET", "/check-in-proc-api-uat/v1/travel-documents", new);
    test:assertEquals(check r1.getJsonPayload(), {target: "routed", path: "check-in-proc-api/v1/travel-documents"});
    http:Response r2 = check c->execute("GET", "/person-profile-proc-api-uat/v1/a", new);
    test:assertEquals(check r2.getJsonPayload(), {target: "shared", path: "person-profile-proc-api-uat/v1/a"});
    test:assertEquals(c.routedPrefixes(), ["/check-in-proc-api/v1"]);
}
