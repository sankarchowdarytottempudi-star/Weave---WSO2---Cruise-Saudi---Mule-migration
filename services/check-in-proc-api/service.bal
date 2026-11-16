import check_in_proc_api.core;

import ballerina/http;
import ballerina/log;
import ballerinax/prometheus as _;
import aroya/integration_commons as commons;

// check-in-proc-api, ported by hand from the Mule application. Every operation is one call to
// the Otalio System API; the answer goes back as it arrived.
//
//   GET  /travelDocuments              -> GET  integration-tasks  operationName=getAllDocuments
//   POST /uploadDocuments              -> POST integration-tasks  operationName=customAttributesCheckIn,
//                                         the caller's operationName (with httpMethod and shipId),
//                                         or uploadDocuments when the caller names none
//   GET  /travel-documents/{id}        -> GET  integration-tasks  operationName=getDocumentsId,
//                                         showPersonPicture or deleteCustomValue, shipId={id}
//   POST /travel-documents/{id}/file   -> POST files  operationName=uploadFile or personPicture, shipId={id}
//   POST /paymentToken                 -> POST integration-tasks  operationName=paymentAuthorization
//   PUT  /updateEmergencyContact       -> POST integration-tasks  operationName=updateEmergencyContact,
//                                         httpMethod=PUT, shipId=<query id>
//   GET  /getLinkedPerson              -> GET  integration-tasks  operationName=getLinkedPerson, shipId=<query id>
//
// Kept from Mule: uploadDocuments, the file upload and paymentToken answer with the backend's
// success status, the other operations with 200; a backend error is answered with the backend's
// status and body; a call is repeated only when `httpRetryCount` allows it (0 in the uploaded
// settings); an error record goes to Kafka, off the request, only when `audit.errorEnabled` is set.
// Different from Mule on purpose: nothing of a request or an answer is written to the log, and a
// message about a failed connection never contains an address.

listener http:Listener httpListener = new (httpPort, host = httpHost, timeout = 60);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    string[] notSet = [];
    if core:isPlaceholderAddress(otalioSystemApi.url) {
        notSet.push("otalioSystemApi.url");
    }
    log:printInfo("check-in-proc-api starting", env = env, basePath = basePath, settingsNotSet = notSet,
            errorRecordsToKafka = audit.errorEnabled);
}

final http:Service apiService = isolated service object {

    isolated resource function get travelDocuments(http:Request request) returns http:Response {
        return relay(core:allDocumentsCall(), request);
    }

    isolated resource function post uploadDocuments(http:Request request) returns http:Response {
        return relay(core:uploadDocumentsCall(request.getQueryParamValue("operationName"),
                request.getQueryParamValue("httpMethod"), request.getQueryParamValue("id")), request);
    }

    isolated resource function get travel\-documents/[string id](http:Request request) returns http:Response {
        return relay(core:documentCall(id, request.getQueryParamValue("operationName")), request);
    }

    isolated resource function post travel\-documents/[string id]/file(http:Request request) returns http:Response {
        return relay(core:fileUploadCall(id, request.getQueryParamValue("operationName")), request);
    }

    isolated resource function post paymentToken(http:Request request) returns http:Response {
        return relay(core:paymentTokenCall(commons:headerOf(request, "Authorization")), request);
    }

    isolated resource function put updateEmergencyContact(http:Request request) returns http:Response {
        return relay(core:emergencyContactCall(request.getQueryParamValue("id")), request);
    }

    isolated resource function get getLinkedPerson(http:Request request) returns http:Response {
        return relay(core:linkedPersonCall(request.getQueryParamValue("id")), request);
    }

    // Anything else: the answers of the Mule router (404 "Resource not found", 405 "Method not allowed").
    isolated resource function 'default [string... path](http:Request request) returns http:Response {
        [int, map<json>] [status, answer] = core:routerAnswerOf(path);
        return jsonAnswer(status, answer, commons:correlationIdOf(request));
    }
};

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}
