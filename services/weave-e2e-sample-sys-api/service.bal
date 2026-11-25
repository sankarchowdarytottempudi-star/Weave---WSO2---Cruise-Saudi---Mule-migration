import ballerina/http;
import ballerina/log;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;

// weave-e2e-sample-sys-api on WSO2 (Ballerina): generated skeleton. Every resource answers NOT_IMPLEMENTED
// until its logic is migrated (see the Mapping document).

listener http:Listener httpListener = new (httpPort);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    log:printInfo("weave-e2e-sample-sys-api starting", env = env, basePath = basePath);
}

final http:Service apiService = isolated service object {
    # Source: GET /api/sample/v1/items (get:\items:sample-api-config)
    // source-forward: GET /items on catalogueRequestConfig (decided in the Factory, 2026-11-15)
    isolated resource function get items(http:Request request) returns http:Response {
        return forwardCall(catalogueRequestConfigForward, request, "GET", "/items", "GET /api/sample/v1/items");
    }

    # Source: GET /api/sample/v1/items/(itemId) (get:\items\(itemId):sample-api-config)
    // source-forward: GET /items/{itemId} on catalogueRequestConfig (decided in the Factory, 2026-11-15)
    isolated resource function get items/[string itemId](http:Request request) returns http:Response {
        return forwardCall(catalogueRequestConfigForward, request, "GET", string `/items/${itemId}`, "GET /api/sample/v1/items/(itemId)");
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

// ---- forwarding (written by the Factory from a decision in "Finish this migration")
// An operation that only passes the call on: the caller's body, query and headers go to the
// backend, and the backend's own status and body come back. A backend that cannot be reached is
// answered in the common error format.
isolated function forwardCall(http:Client|http:ClientError target, http:Request request, string method, string path,
        string sourceEndpoint) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    if target is http:ClientError {
        log:printError("Backend address is not usable", target, correlationId = correlationId,
                sourceEndpoint = sourceEndpoint);
        return commons:errorResponse(commons:envelopeOf(commons:SERVICE_UNAVAILABLE,
                "The backend of " + sourceEndpoint + " has no usable address", correlationId));
    }
    request.setHeader(commons:CORRELATION_HEADER, correlationId);      // the backend's log lines carry the same id
    int? mark = request.rawPath.indexOf("?");
    string query = mark is int ? request.rawPath.substring(mark) : "";
    http:Response|http:ClientError reply = target->execute(method, path + query, request);
    if reply is http:ClientError {
        log:printError("Backend call failed", reply, correlationId = correlationId, sourceEndpoint = sourceEndpoint);
        return commons:errorResponse(commons:envelopeOf(commons:errorTypeOfClientError(reply),
                "The backend of " + sourceEndpoint + " could not be reached", correlationId));
    }
    return reply;
}

final http:Client|http:ClientError catalogueRequestConfigForward = commons:newDownstreamClient(catalogueRequestConfig);
