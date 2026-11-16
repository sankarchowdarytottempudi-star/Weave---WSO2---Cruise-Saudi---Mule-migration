import check_in_proc_api.core;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/mime;
import aroya/integration_commons as commons;

const OTALIO = "otalio-sys-api";

final http:Client otalioClient = check commons:newDownstreamClient(otalioSystemApi);

// Mule: Apache_Kafka_Producer_configuration. The service starts without Kafka: when the
// producer cannot be made, error records stay log lines.
final commons:AuditSink errorSink = errorSinkOf();

function errorSinkOf() returns commons:AuditSink {
    commons:AuditSink|error sink = commons:newAuditSink(audit);
    if sink is error {
        log:printWarn("Kafka cannot be used with the current settings; error records are log lines only");
        return new commons:NoopAuditSink();
    }
    return sink;
}

isolated function jsonAnswer(int status, json answer, string correlationId) returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload(answer);
    response.setHeader(commons:CORRELATION_HEADER, correlationId);
    return response;
}

isolated function notSet(string setting, string correlationId) returns http:Response =>
    commons:errorResponse(commons:envelopeOf(commons:SERVICE_UNAVAILABLE,
                    "The backend address is not set: " + setting, correlationId));

# Makes one call to the Otalio System API for the caller and answers with what it said.
#
# + call - What to send (core:*Call)
# + request - The caller's request
# + return - The answer for the caller
isolated function relay(core:Call call, http:Request request) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    string operation = call.pathKey;
    if core:isPlaceholderAddress(otalioSystemApi.url) {
        return notSet("otalioSystemApi.url", correlationId);
    }
    string? path = core:pathOf(otalioBasePath, otalioPaths, call.pathKey);
    if path is () {
        return notSet("otalioPaths." + call.pathKey, correlationId);
    }
    string target = core:withQuery(path, call.query);
    string contentType = request.getContentType();
    byte[] content = [];
    mime:Entity[]? parts = ();
    json requestRecord = ();
    if call.body == core:UPLOAD {
        // A multipart body is not exposed as bytes; the parsed parts are sent on (same parts,
        // a fresh boundary).
        if !core:baseMediaTypeOf(contentType).startsWith("multipart/") {
            return jsonAnswer(415, {"message": "Unsupported media type"}, correlationId);
        }
        mime:Entity[]|http:ClientError read = request.getBodyParts();
        if read is http:ClientError {
            return jsonAnswer(400, {"message": "Bad request"}, correlationId);
        }
        parts = read;
        requestRecord = core:uploadRecordOf(contentType, read.length());
    } else if call.body != core:NO_BODY {
        byte[]|http:ClientError read = request.getBinaryPayload();
        if read is byte[] {
            content = read;
            requestRecord = core:bodyRecordOf(contentType, read);
        }
    }

    int retriesLeft = httpRetryCount;
    while true {
        http:Request out = new;
        if parts is mime:Entity[] {
            out.setBodyParts(parts, core:baseMediaTypeOf(contentType));
        } else if call.body == core:JSON_BODY {
            if content.length() > 0 {
                out.setBinaryPayload(content, "application/json");
            } else {
                out.setHeader("Content-Type", "application/json");
            }
        } else if call.body == core:CALLER_BODY && content.length() > 0 {
            out.setBinaryPayload(content, contentType == "" ? "application/json" : contentType);
        }
        foreach [string, string] [name, value] in call.headers.entries() {
            out.setHeader(name, value);
        }
        out.setHeader(commons:CORRELATION_HEADER, correlationId);

        http:Response|http:ClientError reply = otalioClient->execute(call.method, target, out);
        if reply is http:ClientError {
            string errorType = commons:errorTypeOfClientError(reply);
            if core:shouldRetry(errorType, httpErrorTypes, retriesLeft) {
                retriesLeft -= 1;
                log:printWarn("Backend call failed, repeating", correlationId = correlationId, operation = operation,
                        backend = OTALIO, errorType = errorType, retriesLeft = retriesLeft);
                runtime:sleep(httpRetryFrequencySeconds);
                continue;
            }
            log:printError("Backend call failed", correlationId = correlationId, operation = operation,
                    backend = OTALIO, errorType = errorType);
            map<json> answer = core:customErrorOf(errorType, (errorType == commons:TIMEOUT
                        ? "The backend did not answer in time: " : "The backend could not be reached: ") + OTALIO, ());
            recordFailure(correlationId, requestRecord, answer);
            return jsonAnswer(core:errorStatusOf(()), answer, correlationId);
        }
        int status = reply.statusCode;
        log:printInfo("Backend answered", correlationId = correlationId, operation = operation, backend = OTALIO,
                status = status);
        if core:isSuccess(status) {
            return successAnswer(reply, call.backendStatus, correlationId);
        }
        string errorType = commons:errorTypeOfStatus(status);
        if core:shouldRetry(errorType, httpErrorTypes, retriesLeft) {
            retriesLeft -= 1;
            byte[]|http:ClientError discarded = reply.getBinaryPayload();
            log:printWarn("Backend answered with an error, repeating", correlationId = correlationId,
                    operation = operation, backend = OTALIO, status = status, retriesLeft = retriesLeft,
                    answerRead = discarded is byte[]);
            runtime:sleep(httpRetryFrequencySeconds);
            continue;
        }
        return backendError(reply, errorType, requestRecord, correlationId);
    }
}

# The backend's successful answer for the caller: its body and content type, and its status
# for the operations that pass it on (200 for the others).
#
# + reply - The backend's answer
# + backendStatus - True when the backend's status is passed on
# + correlationId - The request's correlation id
# + return - The answer for the caller
isolated function successAnswer(http:Response reply, boolean backendStatus, string correlationId) returns http:Response {
    byte[]|http:ClientError content = reply.getBinaryPayload();
    if content is http:ClientError {
        log:printError("The backend's answer could not be read", correlationId = correlationId, backend = OTALIO);
        return jsonAnswer(500, core:customErrorOf(commons:CONNECTIVITY,
                "The backend's answer could not be read: " + OTALIO, ()), correlationId);
    }
    http:Response response = new;
    response.statusCode = core:answerStatusOf(backendStatus, reply.statusCode);
    response.setHeader(commons:CORRELATION_HEADER, correlationId);
    if content.length() > 0 && response.statusCode != 204 {
        string contentType = reply.getContentType();
        response.setBinaryPayload(content, contentType == "" ? "application/json" : contentType);
    }
    return response;
}

# Mule Global_Error_Handler: the backend's error body and status; when it gave no body, the
# custom error with its status.
#
# + reply - The backend's error answer
# + errorType - Error type of its status
# + requestRecord - The caller's request as it would be recorded
# + correlationId - The request's correlation id
# + return - The answer for the caller
isolated function backendError(http:Response reply, string errorType, json requestRecord, string correlationId)
        returns http:Response {
    int status = reply.statusCode;
    byte[]|http:ClientError content = reply.getBinaryPayload();
    if content is http:ClientError || content.length() == 0 {
        map<json> answer = core:customErrorOf(errorType,
                "The backend answered with an error and no detail: " + OTALIO, status);
        recordFailure(correlationId, requestRecord, answer);
        return jsonAnswer(core:errorStatusOf(status), answer, correlationId);
    }
    string contentType = reply.getContentType();
    recordFailure(correlationId, requestRecord, core:bodyRecordOf(contentType, content));
    http:Response response = new;
    response.statusCode = core:errorStatusOf(status);
    response.setBinaryPayload(content, contentType == "" ? "application/json" : contentType);
    response.setHeader(commons:CORRELATION_HEADER, correlationId);
    return response;
}

// source-entry: kafka - Mule: the async scope of Global_Error_Handler and the sub-flow `kafka`.
// The record ([request, {errorMessage: error body}], key = correlation id) is written off the
// request, so the caller never waits for Kafka and never sees a failed publish.
isolated function recordFailure(string correlationId, json requestRecord, json errorBody) {
    if !audit.errorEnabled {
        return;
    }
    if !core:isPublishable(requestRecord, errorBody) {
        log:printWarn("Empty request or error body, no error record written", correlationId = correlationId);
        return;
    }
    future<()> _ = start publishFailure(correlationId, requestRecord.cloneReadOnly(), errorBody.cloneReadOnly());
}

isolated function publishFailure(string correlationId, json & readonly requestRecord, json & readonly errorBody) {
    errorSink.failure(correlationId, requestRecord, errorBody);
}
