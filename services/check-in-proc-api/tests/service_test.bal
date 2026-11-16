import ballerina/http;
import ballerina/mime;
import ballerina/test;

// The HTTP layer, tested on this machine only: the service listens on 127.0.0.1 and calls a
// stand-in for the Otalio System API defined here (on the loopback address 127.0.0.2, because
// 127.0.0.1 counts as "address not set"). All data is made up.

listener http:Listener otalioStandIn = new (18951, host = "127.0.0.2");

// What the stand-in received last, by operationName.
map<string> seen = {};

service /otalio\-sys\-api\-new/v1 on otalioStandIn {
    resource function 'default [string... path](http:Request request) returns http:Response {
        string operation = request.getQueryParamValue("operationName") ?: "";
        string shipId = request.getQueryParamValue("shipId") ?: "-";
        lock {
            seen[operation] = string `${request.method} /${string:'join("/", ...path)} shipId=${shipId} httpMethod=${
                request.getQueryParamValue("httpMethod") ?: "-"} authorization=${
                request.hasHeader("Authorization") ? "sent" : "-"}`;
        }
        http:Response response = new;
        if path.length() > 0 && path[path.length() - 1] == "files" {
            mime:Entity[]|http:ClientError parts = request.getBodyParts();
            if parts is http:ClientError {
                response.statusCode = 400;
                return response;
            }
            response.statusCode = 201;
            response.setJsonPayload({parts: parts.length()});
            return response;
        }
        if operation == "uploadDocuments" {
            response.statusCode = 201;
            response.setJsonPayload({created: true});
        } else if operation == "paymentAuthorization" {
            response.statusCode = 502;
        } else if operation == "showPersonPicture" {
            response.setBinaryPayload([1, 2, 3, 255], "image/png");
        } else if operation == "getLinkedPerson" && shipId == "missing" {
            response.statusCode = 404;
            response.setJsonPayload({reason: "not found"});
        } else {
            response.setJsonPayload({operation});
        }
        return response;
    }
}

final http:Client api = check new ("http://127.0.0.1:18941");
const BASE = "/check-in-proc-api/v1";

function seenFor(string operation) returns string? {
    lock {
        return seen[operation];
    }
}

@test:Config {}
function travelDocumentsAnswersWithTheBackendBody() returns error? {
    http:Response answer = check api->get(BASE + "/travelDocuments", {"correlationId": "test-1"});
    test:assertEquals(answer.statusCode, 200);
    test:assertEquals(check answer.getJsonPayload(), {operation: "getAllDocuments"});
    test:assertEquals(check answer.getHeader("correlationId"), "test-1");
    test:assertEquals(seenFor("getAllDocuments"), "GET /integration-tasks shipId=- httpMethod=- authorization=-");
}

@test:Config {}
function uploadDocumentsPassesTheBackendStatusOn() returns error? {
    http:Response answer = check api->post(BASE + "/uploadDocuments", {name: "made up"});
    test:assertEquals(answer.statusCode, 201);
    test:assertEquals(check answer.getJsonPayload(), {created: true});
    test:assertEquals(seenFor("uploadDocuments"), "POST /integration-tasks shipId=- httpMethod=- authorization=-");
}

@test:Config {}
function uploadDocumentsSendsTheCallersOperation() returns error? {
    http:Response answer = check api->post(BASE + "/uploadDocuments?operationName=madeUpOperation&httpMethod=PATCH&id=7",
        {name: "made up"});
    test:assertEquals(answer.statusCode, 200);
    test:assertEquals(seenFor("madeUpOperation"), "POST /integration-tasks shipId=7 httpMethod=PATCH authorization=-");
}

@test:Config {}
function documentByIdSendsTheIdAsShipId() returns error? {
    http:Response answer = check api->get(BASE + "/travel-documents/5");
    test:assertEquals(answer.statusCode, 200);
    test:assertEquals(seenFor("getDocumentsId"), "GET /integration-tasks shipId=5 httpMethod=- authorization=-");
}

@test:Config {}
function pictureComesBackUnchanged() returns error? {
    http:Response answer = check api->get(BASE + "/travel-documents/5?operationName=showPersonPicture");
    test:assertEquals(answer.statusCode, 200);
    test:assertEquals(check answer.getBinaryPayload(), <byte[]>[1, 2, 3, 255]);
    test:assertEquals(answer.getContentType(), "image/png");
}

@test:Config {}
function fileUploadSendsThePartsOn() returns error? {
    mime:Entity part = new;
    part.setContentDisposition(mime:getContentDispositionObject("form-data; name=\"file\"; filename=\"made-up.txt\""));
    part.setText("made up");
    http:Request upload = new;
    upload.setBodyParts([part], mime:MULTIPART_FORM_DATA);
    http:Response answer = check api->post(BASE + "/travel-documents/5/file?operationName=uploadFile", upload);
    test:assertEquals(answer.statusCode, 201);
    test:assertEquals(check answer.getJsonPayload(), {parts: 1});
    test:assertEquals(seenFor("uploadFile"), "POST /files shipId=5 httpMethod=- authorization=-");
}

@test:Config {}
function fileUploadThatIsNotMultipartIsRefused() returns error? {
    http:Response answer = check api->post(BASE + "/travel-documents/5/file", {name: "made up"});
    test:assertEquals(answer.statusCode, 415);
    test:assertEquals(check answer.getJsonPayload(), {message: "Unsupported media type"});
}

@test:Config {}
function paymentTokenErrorWithoutBodyBecomesTheCustomError() returns error? {
    http:Response answer = check api->post(BASE + "/paymentToken", {amount: 1}, {"Authorization": "Bearer made-up"});
    test:assertEquals(answer.statusCode, 502);
    json body = check answer.getJsonPayload();
    test:assertEquals(check body.errorDoesNotExist, false);
    test:assertEquals(seenFor("paymentAuthorization"), "POST /integration-tasks shipId=- httpMethod=- authorization=sent");
}

@test:Config {}
function emergencyContactIsSentAsPut() returns error? {
    http:Response answer = check api->put(BASE + "/updateEmergencyContact?id=9", {name: "made up"});
    test:assertEquals(answer.statusCode, 200);
    test:assertEquals(seenFor("updateEmergencyContact"), "POST /integration-tasks shipId=9 httpMethod=PUT authorization=-");
}

@test:Config {}
function backendErrorIsPassedOn() returns error? {
    http:Response answer = check api->get(BASE + "/getLinkedPerson?id=missing");
    test:assertEquals(answer.statusCode, 404);
    test:assertEquals(check answer.getJsonPayload(), {reason: "not found"});
}

@test:Config {}
function linkedPersonAnswersTwoHundred() returns error? {
    http:Response answer = check api->get(BASE + "/getLinkedPerson?id=3");
    test:assertEquals(answer.statusCode, 200);
    test:assertEquals(seenFor("getLinkedPerson"), "GET /integration-tasks shipId=3 httpMethod=- authorization=-");
}

@test:Config {}
function unknownPathAndMethodGetTheRouterAnswers() returns error? {
    http:Response notFound = check api->get(BASE + "/nothing");
    test:assertEquals(notFound.statusCode, 404);
    test:assertEquals(check notFound.getJsonPayload(), {message: "Resource not found"});
    http:Response notAllowed = check api->delete(BASE + "/travelDocuments");
    test:assertEquals(notAllowed.statusCode, 405);
    test:assertEquals(check notAllowed.getJsonPayload(), {message: "Method not allowed"});
}

@test:Config {}
function healthAnswers() returns error? {
    json live = check api->get("/health/live");
    test:assertEquals(live, {status: "UP"});
    json ready = check api->get("/health/ready");
    test:assertEquals(ready, {status: "UP"});
}
