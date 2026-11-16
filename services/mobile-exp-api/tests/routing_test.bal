import ballerina/http;
import ballerina/test;

// Calls through the shared connection whose base path is routed (check-in) reach the routed
// service with the old base path replaced; the others still use the shared address.

isolated int routedHits = 0;
isolated string lastRoutedPath = "";

listener http:Listener routedListener = new (19591);

service /routed on routedListener {
    resource function 'default [string... path](http:Request req) returns json {
        lock {
            routedHits += 1;
        }
        string joined = string:'join("/", ...path);
        lock {
            lastRoutedPath = joined;
        }
        return {data: []};
    }
}

@test:Config {}
function checkInCallsGoToTheRoutedService() returns error? {
    int before;
    lock {
        before = routedHits;
    }
    http:Response _ = check call("GET", "/mobile-exp-api/v1/pms/v1/travel-documents", {"Authorization": "Bearer <accessToken>"}, (), "application/json");
    int after;
    lock {
        after = routedHits;
    }
    string path;
    lock {
        path = lastRoutedPath;
    }
    test:assertTrue(after > before, "the travel-documents call did not reach the routed check-in service");
    test:assertTrue(path.startsWith("check-in-proc-api/v1/"), "old base path not replaced: " + path);
    test:assertFalse(path.includes("-uat") || path.includes("-test"), "environment ending kept: " + path);
}

@test:Config {}
function routedPrefixesAreListed() {
    test:assertEquals(hTTPRequestAllProcsClient.routedPrefixes(), ["/check-in-proc-api/v1"]);
}
