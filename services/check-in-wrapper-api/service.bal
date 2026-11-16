import ballerina/http;
import ballerina/log;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;

// check-in-wrapper-api on WSO2 (Ballerina): generated skeleton. Every resource answers NOT_IMPLEMENTED
// until its logic is migrated (see the Mapping document).

listener http:Listener httpListener = new (httpPort);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    log:printInfo("check-in-wrapper-api starting", env = env, basePath = basePath);
}

final http:Service apiService = isolated service object {
    # Source: POST /api/mobile/check-in (checkInInfo)
    isolated resource function post api/mobile/check\-in(http:Request request) returns http:Response {
        return notImplemented(request, "POST /api/mobile/check-in");
    }

    # Source: POST /api/mobile/check-in/submit (checkInSubmit)
    isolated resource function post api/mobile/check\-in/submit(http:Request request) returns http:Response {
        return notImplemented(request, "POST /api/mobile/check-in/submit");
    }

    # Source: POST /api/mobile/check-in/manual-retry (manualCheckInRetry)
    isolated resource function post api/mobile/check\-in/manual\-retry(http:Request request) returns http:Response {
        return notImplemented(request, "POST /api/mobile/check-in/manual-retry");
    }

    # Source: GET /api/mobile/check-in/status (checkInStatus)
    isolated resource function get api/mobile/check\-in/status(http:Request request) returns http:Response {
        return notImplemented(request, "GET /api/mobile/check-in/status");
    }

    # Source: PUT /api/mobile/check-in/reset (checkInReset)
    isolated resource function put api/mobile/check\-in/reset(http:Request request) returns http:Response {
        return notImplemented(request, "PUT /api/mobile/check-in/reset");
    }
};

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}

isolated function notImplemented(http:Request request, string sourceEndpoint) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    log:printWarn("Not migrated yet", correlationId = correlationId, sourceEndpoint = sourceEndpoint);
    return commons:errorResponse(commons:envelopeOf(commons:NOT_IMPLEMENTED, "Not migrated yet: " + sourceEndpoint,
            correlationId));
}
