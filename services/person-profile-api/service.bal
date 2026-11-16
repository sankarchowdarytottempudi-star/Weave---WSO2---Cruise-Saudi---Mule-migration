import person_profile_api.core;

import ballerina/http;
import ballerina/log;
import ballerinax/prometheus as _;
import aroya/integration_commons as commons;

// person-profile-api, ported by hand from the Mule application person-profile-proc-api 1.0.8.
// Every operation is one call to the Otalio System API (`otalioPath`, Mule
// `personprofileConfigDetails.path`); the answer goes back as it arrived.
//
//   GET  /getEventsFolio                         -> GET  operationName=getEventsFolio, page, search, size, sort
//   GET  /getamenity                             -> GET  operationName=getamenity, search
//   GET  /getamenity-codes                       -> GET  operationName=getamenity-codes, search
//   GET  /pos/v1/packages                        -> GET  operationName=getPackages, search
//   GET  /reservation/v1/person-search           -> GET  operationName=getPersonSearch + every caller parameter
//   GET  /reservation/v1/person-search/{id}      -> GET  operationName=getPersonByReservationID, shipId={id} + parameters
//   GET  /reservation/v1/reservation-search/{id} -> GET  operationName=getReservationByID, shipId={id} + parameters
//   POST /integration/v1/messages/statuses       -> POST operationName=statusmessage, caller's body
//   POST /integration/v1/messages                -> POST operationName=sendmessage, caller's body
//   POST /reservation/v1/person-reservations/actions/bulk-update
//                                                -> POST operationName=bulkUpdateReservations, httpMethod=PATCH, body
//
// Kept from Mule: a success is answered 200 with the backend's body; a backend error with the
// backend's status and body (or the custom error when it gave none, 500 when it did not answer);
// a call is repeated only when `httpRetryCount` allows it (0 in the uploaded settings); the
// APIkit answers 400/404/405/415 with their bodies; an error record goes to Kafka, off the
// request, only when `audit.errorEnabled` is set (false in the uploaded settings).
// Different from Mule on purpose: request and answer bodies are not written to the log (Mule
// logged every payload), and a message about a failed connection never contains an address.

listener http:Listener httpListener = new (httpPort, host = httpHost, timeout = 30);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    string[] notSet = [];
    if core:isPlaceholderAddress(otalioSystemApi.url) {
        notSet.push("otalioSystemApi.url");
    }
    log:printInfo("person-profile-api starting", env = env, basePath = basePath, settingsNotSet = notSet,
            errorRecordsToKafka = audit.errorEnabled);
}

isolated function refused(int status, map<json> answer, http:Request request) returns http:Response =>
    jsonAnswer(status, answer, commons:correlationIdOf(request));

# Reads and checks a POST body the way APIkit did, then relays it.
#
# + call - The call
# + request - The caller's request
# + wanted - "array" (required JSON array) or "object" (optional JSON object)
# + return - The answer for the caller
isolated function relayBody(core:Call call, http:Request request, string wanted) returns http:Response {
    byte[]|http:ClientError content = request.getBinaryPayload();
    if content is http:ClientError {
        return refused(400, {"message": core:BAD_REQUEST}, request);
    }
    [int, map<json>]? refusal = core:bodyRefusalOf(request.getContentType(), content, wanted);
    if refusal is [int, map<json>] {
        return refused(refusal[0], refusal[1], request);
    }
    return relay(call, request, content);
}

final http:Service apiService = isolated service object {

    isolated resource function get getEventsFolio(http:Request request) returns http:Response {
        string? page = request.getQueryParamValue("page");
        string? size = request.getQueryParamValue("size");
        if !core:isIntegerOrAbsent(page) || !core:isIntegerOrAbsent(size) {
            return refused(400, {"message": core:BAD_REQUEST}, request);
        }
        return relay(core:eventsFolioCall(page, request.getQueryParamValue("search"), size,
                request.getQueryParamValue("sort")), request);
    }

    isolated resource function get getamenity(http:Request request) returns http:Response {
        return relay(core:amenityCall(request.getQueryParamValue("search")), request);
    }

    isolated resource function get getamenity\-codes(http:Request request) returns http:Response {
        return relay(core:amenityCodesCall(request.getQueryParamValue("search")), request);
    }

    isolated resource function get pos/v1/packages(http:Request request) returns http:Response {
        return relay(core:packagesCall(request.getQueryParamValue("search")), request);
    }

    isolated resource function get reservation/v1/person\-search(http:Request request) returns http:Response {
        return relay(core:personSearchCall(core:pairsOf(request.getQueryParams())), request);
    }

    isolated resource function get reservation/v1/person\-search/[string reservationId](http:Request request)
            returns http:Response {
        return relay(core:personByReservationCall(reservationId, core:pairsOf(request.getQueryParams())), request);
    }

    isolated resource function get reservation/v1/reservation\-search/[string reservationId](http:Request request)
            returns http:Response {
        return relay(core:reservationByIdCall(reservationId, core:pairsOf(request.getQueryParams())), request);
    }

    isolated resource function post integration/v1/messages/statuses(http:Request request) returns http:Response {
        return relayBody(core:messageStatusesCall(clientNameOf(request)), request, "array");
    }

    isolated resource function post integration/v1/messages(http:Request request) returns http:Response {
        return relayBody(core:messagesCall(clientNameOf(request)), request, "array");
    }

    isolated resource function post reservation/v1/person\-reservations/actions/bulk\-update(http:Request request)
            returns http:Response {
        return relayBody(core:bulkUpdateCall(clientNameOf(request)), request, "object");
    }

    // Anything else: the answers of the Mule router (404 "Resource not found", 405 "Method not allowed").
    isolated resource function 'default [string... path](http:Request request) returns http:Response {
        [int, map<json>] [status, answer] = core:routerAnswerOf(path);
        return jsonAnswer(status, answer, commons:correlationIdOf(request));
    }
};

// Mule: `attributes.headers.client_name default "MuleSoft"` (the default is applied in core:post).
isolated function clientNameOf(http:Request request) returns string? {
    string|http:HeaderNotFoundError value = request.getHeader("client_name");
    return value is string ? value : ();
}

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}
