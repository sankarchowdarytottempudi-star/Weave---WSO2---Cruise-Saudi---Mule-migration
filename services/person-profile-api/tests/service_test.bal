import ballerina/http;
import ballerina/test;

// The HTTP layer, tested on this machine only: the service listens on 127.0.0.1 and calls a
// stand-in for the Otalio System API (on 127.0.0.2, because 127.0.0.1 counts as "address not set").

listener http:Listener otalioStandIn = new (18971, host = "127.0.0.2");

map<string> seen = {};
int unavailableCalls = 0;

service /otalio\-sys\-api\-new/v1 on otalioStandIn {
    resource function 'default integration\-tasks(http:Request request) returns http:Response|error {
        string operation = request.getQueryParamValue("operationName") ?: "";
        byte[] body = check request.getBinaryPayload();
        lock {
            seen[operation] = string `${request.method} ${request.rawPath} client=${
                request.hasHeader("client_name") ? check request.getHeader("client_name") : "-"} body=${
                check string:fromBytes(body)}`;
        }
        http:Response response = new;
        string search = request.getQueryParamValue("search") ?: "";
        if search == "missing" {
            response.statusCode = 404;
            response.setJsonPayload({reason: "not found"});
        } else if search == "empty-error" {
            response.statusCode = 502;
        } else if search == "busy" {
            lock {
                unavailableCalls += 1;
            }
            response.statusCode = 503;
            response.setJsonPayload({reason: "busy"});
        } else if operation == "sendmessage" {
            response.statusCode = 201;
            response.setJsonPayload({sent: true});
        } else if operation == "statusmessage" {
            response.statusCode = 204;
        } else {
            response.setJsonPayload({operation});
        }
        return response;
    }
}

final http:Client api = check new ("http://127.0.0.1:18961");
const BASE = "/person-profile-proc-api/v1";

function seenFor(string operation) returns string {
    lock {
        return seen[operation] ?: "";
    }
}

@test:Config {}
function getOperationsCallOtalio() returns error? {
    http:Response r = check api->get(BASE + "/getEventsFolio?page=1&size=5&search=a%20b");
    test:assertEquals(r.statusCode, 200);
    test:assertEquals(check r.getJsonPayload(), {operation: "getEventsFolio"});
    test:assertEquals(seenFor("getEventsFolio"),
            "GET /otalio-sys-api-new/v1/integration-tasks?operationName=getEventsFolio&page=1&search=a%20b&size=5 client=- body=");
    http:Response _ = check api->get(BASE + "/getamenity?search=pool");
    test:assertEquals(seenFor("getamenity"), "GET /otalio-sys-api-new/v1/integration-tasks?operationName=getamenity&search=pool client=- body=");
    http:Response _ = check api->get(BASE + "/getamenity-codes");
    test:assertEquals(seenFor("getamenity-codes"), "GET /otalio-sys-api-new/v1/integration-tasks?operationName=getamenity-codes client=- body=");
    http:Response _ = check api->get(BASE + "/pos/v1/packages?search=spa&page=3&hierarchyId=9");
    test:assertEquals(seenFor("getPackages"), "GET /otalio-sys-api-new/v1/integration-tasks?operationName=getPackages&search=spa client=- body=");
    http:Response _ = check api->get(BASE + "/reservation/v1/person-search?search=smith&extra=1");
    test:assertEquals(seenFor("getPersonSearch"),
            "GET /otalio-sys-api-new/v1/integration-tasks?operationName=getPersonSearch&search=smith&extra=1 client=- body=");
    http:Response _ = check api->get(BASE + "/reservation/v1/person-search/R100?x=y");
    test:assertEquals(seenFor("getPersonByReservationID"),
            "GET /otalio-sys-api-new/v1/integration-tasks?operationName=getPersonByReservationID&shipId=R100&x=y client=- body=");
    http:Response rs = check api->get(BASE + "/reservation/v1/reservation-search/R200");
    test:assertEquals(rs.statusCode, 200);
    test:assertEquals(seenFor("getReservationByID"),
            "GET /otalio-sys-api-new/v1/integration-tasks?operationName=getReservationByID&shipId=R200 client=- body=");
}

@test:Config {}
function postOperationsPassBodyAndAnswer200() returns error? {
    http:Response r = check api->post(BASE + "/integration/v1/messages", [{"to": "x"}], {"client_name": "mobile"});
    test:assertEquals(r.statusCode, 200, "Mule answers 200 even when the backend said 201");
    test:assertEquals(check r.getJsonPayload(), {sent: true});
    test:assertEquals(seenFor("sendmessage"),
            "POST /otalio-sys-api-new/v1/integration-tasks?operationName=sendmessage client=mobile body=[{\"to\":\"x\"}]");
    http:Response s = check api->post(BASE + "/integration/v1/messages/statuses", [1]);
    test:assertEquals(s.statusCode, 200);
    test:assertEquals(seenFor("statusmessage"),
            "POST /otalio-sys-api-new/v1/integration-tasks?operationName=statusmessage client=MuleSoft body=[1]");
    http:Response b = check api->post(BASE + "/reservation/v1/person-reservations/actions/bulk-update", {"ids": [1]});
    test:assertEquals(b.statusCode, 200);
    test:assertEquals(seenFor("bulkUpdateReservations"),
            "POST /otalio-sys-api-new/v1/integration-tasks?operationName=bulkUpdateReservations&httpMethod=PATCH client=MuleSoft body={\"ids\":[1]}");
    http:Request empty = new;
    http:Response e = check api->post(BASE + "/reservation/v1/person-reservations/actions/bulk-update", empty);
    test:assertEquals(e.statusCode, 200, "bulk-update takes no body");
}

@test:Config {}
function apikitAnswers() returns error? {
    http:Response bad = check api->get(BASE + "/getEventsFolio?page=x");
    test:assertEquals(bad.statusCode, 400);
    test:assertEquals(check bad.getJsonPayload(), {"message": "Bad request"});
    http:Response obj = check api->post(BASE + "/integration/v1/messages", {"a": 1});
    test:assertEquals(obj.statusCode, 400);
    http:Request text = new;
    text.setTextPayload("[1]");
    http:Response media = check api->post(BASE + "/integration/v1/messages", text);
    test:assertEquals(media.statusCode, 415);
    test:assertEquals(check media.getJsonPayload(), {"message": "Unsupported media type"});
    http:Response nf = check api->get(BASE + "/nothing/here");
    test:assertEquals(nf.statusCode, 404);
    test:assertEquals(check nf.getJsonPayload(), {"message": "Resource not found"});
    http:Response na = check api->put(BASE + "/getamenity", {});
    test:assertEquals(na.statusCode, 405);
}

@test:Config {}
function backendErrors() returns error? {
    http:Response nf = check api->get(BASE + "/getamenity?search=missing");
    test:assertEquals(nf.statusCode, 404, "the backend's status and body");
    test:assertEquals(check nf.getJsonPayload(), {reason: "not found"});
    http:Response noBody = check api->get(BASE + "/getamenity?search=empty-error");
    test:assertEquals(noBody.statusCode, 502);
    json answer = check noBody.getJsonPayload();
    test:assertEquals(check answer.messageType, "BAD_GATEWAY");
    test:assertEquals(check answer.responseCode, 502);
    test:assertEquals(check answer.errorDoesNotExist, false);
    http:Response busy = check api->get(BASE + "/getamenity?search=busy");
    test:assertEquals(busy.statusCode, 503);
    lock {
        test:assertEquals(unavailableCalls, 2, "one repeat (httpRetryCount = 1 in the test settings)");
    }
}

@test:Config {}
function healthAnswers() returns error? {
    http:Client health = check new ("http://127.0.0.1:18961");
    http:Response r = check health->get("/health/ready");
    test:assertEquals(r.statusCode, 200);
}
