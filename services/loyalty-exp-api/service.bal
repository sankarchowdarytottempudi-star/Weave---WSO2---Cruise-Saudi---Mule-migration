import ballerina/http;
import ballerina/log;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;

// loyalty-exp-api on WSO2 (Ballerina): generated skeleton. Every resource answers NOT_IMPLEMENTED
// until its logic is migrated (see the Mapping document).

listener http:Listener httpListener = new (httpPort);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    log:printInfo("loyalty-exp-api starting", env = env, basePath = basePath);
}

final http:Service apiService = isolated service object {
    # Source: POST /loyalty/v1/points (getPoints)
    isolated resource function post loyalty/v1/points(http:Request request) returns http:Response {
        return notImplemented(request, "POST /loyalty/v1/points");
    }

    # Source: POST /loyalty/v1/redeem (redeem)
    isolated resource function post loyalty/v1/redeem(http:Request request) returns http:Response {
        return notImplemented(request, "POST /loyalty/v1/redeem");
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
