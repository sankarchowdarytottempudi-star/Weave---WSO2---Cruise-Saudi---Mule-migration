import seaware_sys_api.core;

import ballerina/http;
import ballerina/log;
import ballerinax/jaeger as _;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;

// seaware-sys-api on WSO2 (Ballerina). Replaces the Mule project of the same name.
//
// Contract (unchanged for callers): POST {basePath}/integration-tasks with a GraphQL document
// as the JSON body; the body is sent to Seaware GraphQL as-is with the caller's
// Authorization header and the correlation id; Seaware's answer is returned as-is.
//
// Fixed on the way (see docs/generated/seaware-sys-api/TECHNICAL.md, findings):
//   - the Authorization header is no longer written to the log (the Mule INFO logger did);
//   - TLS certificates are validated (Mule had trust-store insecure="true");
//   - a write (any GraphQL mutation) is sent once and never retried, even if a retry count is
//     configured: after a timeout the first one may still finish in Seaware.

listener http:Listener httpListener = new (httpPort);

final http:Client seawareClient = check commons:newDownstreamClient(seaware);
// Writes: their own, longer time limit, and never repeated (see `writeTimeoutSeconds`).
final http:Client seawareWriteClient = check commons:newDownstreamClient({
    url: seaware.url,
    timeoutSeconds: writeTimeoutSeconds,
    http2: seaware.http2,
    tlsValidation: seaware.tlsValidation,
    caCertPath: seaware.caCertPath
});
final commons:AuditSink auditSink = check commons:newAuditSink(audit);

function init() returns error? {
    check httpListener.attach(sysService, basePath);
    log:printInfo("seaware-sys-api starting", env = env, deploymentTarget = deploymentTarget, basePath = basePath,
            seaware = seaware.url);
}

final http:Service sysService = isolated service object {

    isolated resource function post integration\-tasks(http:Request request) returns http:Response {
        return forwardToSeaware(request);
    }
};

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}

isolated function forwardToSeaware(http:Request request) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    byte[]|http:ClientError body = request.getBinaryPayload();
    if body is http:ClientError {
        return commons:errorResponse(commons:envelopeOf(commons:BAD_REQUEST, "The request body could not be read",
                        correlationId));
    }
    string query = core:queryTextOf(body);
    string? operation = commons:rootFieldOf(query);
    boolean write = core:isWrite(query);
    http:Client target = write ? seawareWriteClient : seawareClient;
    map<string> headers = core:seawareHeaders(commons:headerOf(request, "Authorization"), correlationId, commons:headerOf(request, "X-Seaware-Authorization"));
    log:printInfo("Requesting Seaware", correlationId = correlationId, operation = operation ?: "UNKNOWN", seawareSession = commons:headerOf(request, "X-Seaware-Authorization") is string);

    int maxAttempts = retryPolicy.count + 1;
    commons:ErrorEnvelope lastError = commons:envelopeOf(commons:CONNECTIVITY, "Seaware was not called", correlationId);
    foreach int attempt in 1 ... maxAttempts {
        http:Response|http:ClientError reply = target->post(seawarePath, body, headers);
        if reply is http:Response && reply.statusCode < 400 {
            log:printInfo("Seaware response received", correlationId = correlationId, status = reply.statusCode,
                    attempt = attempt);
            reply.setHeader(commons:CORRELATION_HEADER, correlationId);
            return reply;
        }
        string errorType;
        if reply is http:Response {
            errorType = commons:errorTypeOfStatus(reply.statusCode);
            if write || !commons:isRetryable(retryPolicy, operation, errorType, attempt) {
                log:printError("Seaware answered an error", correlationId = correlationId, status = reply.statusCode,
                        errorType = errorType);
                return downstreamError(reply, errorType, correlationId, body);
            }
        } else {
            errorType = commons:errorTypeOfClientError(reply);
            lastError = commons:envelopeOf(errorType, reply.message(), correlationId);
            if write || !commons:isRetryable(retryPolicy, operation, errorType, attempt) {
                log:printError("Seaware call failed", correlationId = correlationId, errorType = errorType,
                        'error = reply);
                auditSink.failure(correlationId, core:bodyAsJson(body), lastError.toJson());
                return commons:errorResponse(lastError);
            }
        }
        log:printWarn("Retrying Seaware call", correlationId = correlationId, attempt = attempt, errorType = errorType);
        commons:waitBeforeRetry(retryPolicy, attempt);
    }
    auditSink.failure(correlationId, core:bodyAsJson(body), lastError.toJson());
    return commons:errorResponse(lastError);
}

isolated function downstreamError(http:Response reply, string errorType, string correlationId, byte[] request)
        returns http:Response {
    json|http:ClientError downstream = reply.getJsonPayload();
    json target = downstream is json ? downstream : ();
    commons:ErrorEnvelope envelope = commons:envelopeOf(errorType, core:messageOf(target, errorType), correlationId,
            reply.statusCode, target);
    auditSink.failure(correlationId, core:bodyAsJson(request), envelope.toJson());
    if passThroughDownstreamErrors && target != () {
        http:Response response = new;
        response.statusCode = reply.statusCode;
        response.setJsonPayload(target);
        response.setHeader(commons:CORRELATION_HEADER, correlationId);
        return response;
    }
    return commons:errorResponse(envelope);
}
