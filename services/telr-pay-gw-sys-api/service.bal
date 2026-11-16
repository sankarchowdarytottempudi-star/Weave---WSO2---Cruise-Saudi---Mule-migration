import telr_pay_gw_sys_api.core;

import ballerina/http;
import ballerina/log;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;

// telr-pay-gw-sys-api on WSO2 (Ballerina). Replaces the Mule project of the same name.
//
// Contract (unchanged for callers):
//   POST {basePath}/sessions  body { order:{cartid,amount,currency,description,trantype},
//                                    customer:{ref,email,name:{title,forenames,surname},
//                                              address:{line1,line2,line3,city,state,country,areacode},phone},
//                                    extra:{extra1,extra2,extra3} }
//                             The same body wrapped as { session: {...} } is accepted too.
//                             -> creates a Telr hosted payment session; Telr's answer is returned as-is.
//   POST {basePath}/status    body { orderRef } -> Telr's status answer for that order, as-is.
//   POST {basePath}/webhooks  -> acknowledges Telr's notification: 200 with the body it received.
//
// The store id, the store authentication key, the test flag and the return addresses are added
// here from configuration, exactly as the Mule flow did; callers never send them.
//
// Deliberate differences from Mule:
//   - nothing of the request or of Telr's answer is written to the log (the Mule loggers wrote the
//     payload; the request to Telr contains the store authentication key);
//   - a body that is not JSON, or has no order / orderRef, is refused with 400 instead of being
//     sent to Telr with empty values;
//   - calls to Telr are never retried (same as Mule `httpRetryCount: 0`; a payment must not repeat).

listener http:Listener httpListener = new (httpPort);

final http:Client telrClient = check commons:newDownstreamClient(hTTPRequestConfigurationTelr);

function init() returns error? {
    if core:isPlaceholderAddress(hTTPRequestConfigurationTelr.url) {
        return error("hTTPRequestConfigurationTelr.url is not set; the service does not start without the Telr address");
    }
    check httpListener.attach(apiService, basePath);
    log:printInfo("telr-pay-gw-sys-api starting", env = env, basePath = basePath, testMode = telrStore.orderTest);
}

final commons:AuditSink errorRecordSink = errorRecordSinkOf();

function errorRecordSinkOf() returns commons:AuditSink {
    commons:AuditSink|error sink = commons:newAuditSink(audit);
    return sink is commons:AuditSink ? sink : new commons:NoopAuditSink();
}

isolated service class ErrorRecordedApi {
    *http:InterceptableService;

    // Mule global error handler: every failed call goes to kafka.errorTopic as
    // [saved payload, {"errorMessage": error body}] (off unless switched on in the settings)
    public function createInterceptors() returns http:Interceptor[] => commons:errorRecordInterceptors(errorRecordSink);


    isolated resource function post sessions(http:Request request) returns http:Response {
        return callTelr(request, "sessions");
    }

    isolated resource function post status(http:Request request) returns http:Response {
        return callTelr(request, "status");
    }

    // Mule: log the notification, answer 200 with the payload received.
    isolated resource function post webhooks(http:Request request) returns http:Response {
        string correlationId = commons:correlationIdOf(request);
        byte[]|http:ClientError body = request.getBinaryPayload();
        http:Response response = new;
        response.statusCode = 200;
        response.setHeader(commons:CORRELATION_HEADER, correlationId);
        if body is byte[] && body.length() > 0 {
            string contentType = request.getContentType();
            response.setBinaryPayload(body, contentType == "" ? "application/json" : contentType);
        }
        log:printInfo("Telr notification received", correlationId = correlationId,
                bytes = body is byte[] ? body.length() : 0);
        return response;
    }
}

final ErrorRecordedApi apiService = new;

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}

isolated function callTelr(http:Request request, string operation) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    json|http:ClientError payload = request.getJsonPayload();
    if payload is http:ClientError {
        return commons:errorResponse(commons:envelopeOf(commons:BAD_REQUEST, "The request body must be JSON",
                        correlationId));
    }
    map<json>|error telrRequest = operation == "sessions"
        ? core:sessionRequestOf(payload, telrStore)
        : core:statusRequestOf(payload, telrStore);
    if telrRequest is error {
        return commons:errorResponse(commons:envelopeOf(commons:BAD_REQUEST, telrRequest.message(), correlationId));
    }
    map<string> headers = {"Content-Type": "application/json", "Accept": "application/json"};

    // One attempt only: a payment call is never repeated.
    http:Response|http:ClientError reply = telrClient->post(telrPath, telrRequest.toJsonString().toBytes(), headers);
    if reply is http:ClientError {
        string errorType = commons:errorTypeOfClientError(reply);
        log:printError("Telr call failed", correlationId = correlationId, operation = operation, errorType = errorType);
        return commons:errorResponse(commons:envelopeOf(errorType, "The Telr payment gateway could not be reached",
                        correlationId));
    }
    log:printInfo("Telr answered", correlationId = correlationId, operation = operation, status = reply.statusCode);
    reply.setHeader(commons:CORRELATION_HEADER, correlationId);
    return reply;
}
