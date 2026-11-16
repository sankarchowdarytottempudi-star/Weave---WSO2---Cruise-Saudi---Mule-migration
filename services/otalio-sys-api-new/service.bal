import otalio_sys_api_new.core;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/mime;
import ballerina/time;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;

// otalio-sys-api-new on WSO2 (Ballerina). Replaces the Mule project of the same name.
//
// Operations (paths, query parameters and bodies unchanged for callers):
//   GET  /integration-tasks?operationName=X[&shipId=..][&...]
//        -> GET on Otalio at the path configured for X (`{ID}` in the path = shipId), with the
//           caller's other query parameters. `deleteCustomValue` is sent as DELETE.
//   GET  /integration-tasks?targetPath=/some/otalio/path   (no operationName)
//        -> GET on that Otalio path.
//   POST /integration-tasks?operationName=X[&httpMethod=POST|PATCH|PUT][&...]
//        -> the caller's body to the path configured for X. POST carries the caller's other query
//           parameters; PATCH and PUT do not (as in Mule).
//   POST /files?operationName=X[&shipId=..]   (multipart/form-data)
//        -> the caller's upload, as received, to the path configured for X.
//   POST /integration-tasks/graphql
//        -> the caller's body to Otalio's GraphQL endpoint (no sign-in, as in Mule).
//   Otalio's status and body are returned as they are, errors included.
//
// The service signs in to Otalio itself (Mule `accessTokenFlow`): it logs in with the configured
// account, keeps the refresh token for `refreshTokenSeconds`, exchanges it for an access token and
// sends `Authorization: Bearer <access token>`. The caller's own Authorization header is never
// passed on; the caller's other headers are.
//
// Deliberate differences from Mule:
//   - the access token is reused for up to `accessTokenSeconds` instead of being asked for again on
//     every call; when Otalio answers 401 the service signs in again and repeats the call once;
//   - nothing of a request, an answer or a token is written to the log: only the operation name,
//     the status and the correlation id (the Mule loggers wrote payloads);
//   - error and audit records are not published to Kafka (both switches were off in the uploaded
//     settings); the same events are log lines;
//   - a call without a usable operationName is refused with 400 (Mule answered 200 with the
//     request echoed back), and so is an operationName that has no configured path;
//   - a message about a failed connection never contains an address.

listener http:Listener httpListener = new (httpPort, timeout = 120);

final http:Client otalioClient = check commons:newDownstreamClient(hTTPRequestOtalioSystemConfig);

# Why the service could not sign in to Otalio.
type TokenError error<record {|string errorType;|}>;

isolated core:TokenState tokenState = {};

function init() returns error? {
    log:printInfo("state store", keptIn = state.location());
    check httpListener.attach(apiService, basePath);
    string[] notSet = [];
    if core:isPlaceholderAddress(hTTPRequestOtalioSystemConfig.url) {
        notSet.push("hTTPRequestOtalioSystemConfig.url");
    }
    string? account = core:missingAccountSetting(otalioAccount);
    if account is string {
        notSet.push(account);
    }
    log:printInfo("otalio-sys-api-new starting", env = env, basePath = basePath,
            operations = operationPaths.length(), settingsNotSet = notSet);
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


    isolated resource function get integration\-tasks(http:Request request) returns http:Response {
        return readTask(request);
    }

    isolated resource function post integration\-tasks(http:Request request) returns http:Response {
        return writeTask(request);
    }

    isolated resource function post files(http:Request request) returns http:Response {
        return uploadFile(request);
    }

    isolated resource function post integration\-tasks/graphql(http:Request request) returns http:Response {
        return graphql(request);
    }
}

final ErrorRecordedApi apiService = new;

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}

// ---------------------------------------------------------------------------------------------
// Operations
// ---------------------------------------------------------------------------------------------

// Mule `otalio-sys-api-Get_Implementation_Sub_Flow` and `metadata_implementationSub_Flow`.
isolated function readTask(http:Request request) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    http:Response? notReady = settingsMissing(correlationId);
    if notReady is http:Response {
        return notReady;
    }
    map<string[]> query = request.getQueryParams();
    string? operationName = core:firstOf(query, "operationName");
    if operationName is string {
        string|error path = core:targetPathOf(operationPaths, operationName, core:firstOf(query, "shipId") ?: "");
        if path is error {
            return badRequest(path.message(), correlationId);
        }
        string target = core:withQuery(path, core:without(query, ["operationName"]));
        return callOtalio(core:readMethodOf(operationName), target, passedOnHeaders(request, correlationId), (),
                request.getContentType(), operationName, correlationId);
    }
    string? targetPath = core:firstOf(query, "targetPath");
    if targetPath is string {
        if !core:isSafePath(targetPath) {
            return badRequest("The targetPath is not valid", correlationId);
        }
        // Mule: only Authorization and Content-Type are sent.
        return callOtalio("GET", targetPath, {}, (), "application/json", "targetPath", correlationId);
    }
    return badRequest("Invalid operation name: send operationName (or targetPath)", correlationId);
}

// Mule `otalio-sys-api-Post_implementation_Sub_Flow`.
isolated function writeTask(http:Request request) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    http:Response? notReady = settingsMissing(correlationId);
    if notReady is http:Response {
        return notReady;
    }
    map<string[]> query = request.getQueryParams();
    string? operationName = core:firstOf(query, "operationName");
    if operationName is () {
        return badRequest("Invalid operation name: send operationName", correlationId);
    }
    string|error method = core:writeMethodOf(core:firstOf(query, "httpMethod"));
    if method is error {
        return badRequest(method.message(), correlationId);
    }
    string|error path = core:targetPathOf(operationPaths, operationName, core:firstOf(query, "shipId") ?: "");
    if path is error {
        return badRequest(path.message(), correlationId);
    }
    byte[]|http:ClientError body = request.getBinaryPayload();
    if body is http:ClientError {
        return badRequest("The request body could not be read", correlationId);
    }
    // Mule: POST sends the caller's query parameters, PATCH and PUT send none.
    string target = method == "POST" ? core:withQuery(path, core:without(query, ["operationName", "httpMethod"])) : path;
    string contentType = request.getContentType();
    return callOtalio(method, target, passedOnHeaders(request, correlationId), body,
            contentType == "" ? "application/json" : contentType, operationName, correlationId);
}

// Mule `Files_implementationSub_Flow`: the upload goes to Otalio as it was received, with the
// Authorization header only.
isolated function uploadFile(http:Request request) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    http:Response? notReady = settingsMissing(correlationId);
    if notReady is http:Response {
        return notReady;
    }
    string contentType = request.getContentType();
    if !contentType.toLowerAscii().startsWith("multipart/form-data") {
        http:Response response = new;
        response.statusCode = 415;
        response.setHeader(commons:CORRELATION_HEADER, correlationId);
        response.setJsonPayload({message: "Unsupported media type"});
        return response;
    }
    map<string[]> query = request.getQueryParams();
    string? operationName = core:firstOf(query, "operationName");
    if operationName is () {
        return badRequest("Invalid operation name: send operationName", correlationId);
    }
    string|error path = core:targetPathOf(operationPaths, operationName, core:firstOf(query, "shipId") ?: "");
    if path is error {
        return badRequest(path.message(), correlationId);
    }
    // A multipart body is not exposed through getBinaryPayload()/getByteStream(); forward the parsed
    // parts instead (same parts, re-encoded with a fresh boundary, which any multipart server reads).
    mime:Entity[]|http:ClientError parts = request.getBodyParts();
    if parts is http:ClientError {
        return badRequest("The upload could not be read", correlationId);
    }
    string target = core:withQuery(path, core:without(query, ["operationName"]));
    return callOtalio("POST", target, {}, (), contentType, operationName, correlationId, parts);
}

// Mule `otalio-sys-api-graphQL_implementation_Sub_Flow`: the body to Otalio's GraphQL endpoint,
// without the sign-in.
isolated function graphql(http:Request request) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    if core:isPlaceholderAddress(hTTPRequestOtalioSystemConfig.url) {
        return addressNotSet("hTTPRequestOtalioSystemConfig.url", correlationId);
    }
    byte[]|http:ClientError body = request.getBinaryPayload();
    if body is http:ClientError {
        return badRequest("The request body could not be read", correlationId);
    }
    string contentType = request.getContentType();
    http:Response|http:ClientError reply = sendToOtalio("POST", graphqlPath, {}, (), body,
            contentType == "" ? "application/json" : contentType);
    if reply is http:ClientError {
        return unreachable(reply, "graphql", correlationId);
    }
    return relay(reply, "graphql", correlationId);
}

// ---------------------------------------------------------------------------------------------
// Calls to Otalio
// ---------------------------------------------------------------------------------------------

# One signed-in call to Otalio. When Otalio answers 401 the service signs in again and repeats
# the call once.
#
# + method - HTTP method
# + target - Otalio path with the query parameters
# + headers - Caller's headers that are passed on
# + body - Body to send, `()` for none
# + contentType - Content type of the call ("" for none)
# + operation - Operation name, for the log
# + correlationId - Correlation id
# + return - Otalio's answer, as it is
isolated function callOtalio(string method, string target, map<string[]> headers, byte[]? body, string contentType,
        string operation, string correlationId, mime:Entity[]? parts = ()) returns http:Response {
    string|TokenError authorization = otalioAuthorization("");
    foreach int attempt in 0 ... 1 {
        if authorization is TokenError {
            return signInFailure(authorization, operation, correlationId);
        }
        http:Response|http:ClientError reply = sendToOtalio(method, target, headers, authorization, body, contentType, parts);
        if reply is http:ClientError {
            return unreachable(reply, operation, correlationId);
        }
        if reply.statusCode == 401 && attempt == 0 {
            byte[]|http:ClientError discarded = reply.getBinaryPayload();
            log:printWarn("Otalio refused the access token; signing in again", correlationId = correlationId,
                    operation = operation, answerRead = discarded is byte[]);
            authorization = otalioAuthorization(authorization);
            continue;
        }
        return relay(reply, operation, correlationId);
    }
    return commons:errorResponse(commons:envelopeOf(commons:BAD_GATEWAY, "Otalio refused the service's sign-in",
                    correlationId));
}

# One HTTP call to Otalio, repeated after a pause when Otalio could not be reached and
# `httpRetryCount` allows it (Mule `http-error-retrySub_Flow`: BAD_GATEWAY, CONNECTIVITY, TIMEOUT).
isolated function sendToOtalio(string method, string target, map<string[]> headers, string? authorization,
        byte[]? body, string contentType, mime:Entity[]? parts = ()) returns http:Response|http:ClientError {
    int retriesLeft = httpRetryCount;
    while true {
        http:Request out = new;
        foreach [string, string[]] [name, values] in headers.entries() {
            foreach string value in values {
                out.addHeader(name, value);
            }
        }
        if authorization is string {
            out.setHeader("Authorization", authorization);
        }
        if parts is mime:Entity[] {
            // Re-encode the upload with a fresh boundary (the exact base media type is kept).
            string base = contentType == "" ? mime:MULTIPART_FORM_DATA : baseMediaType(contentType);
            out.setBodyParts(parts, base);
        } else if body is byte[] {
            out.setBinaryPayload(body, contentType == "" ? "application/octet-stream" : contentType);
        } else if contentType != "" {
            out.setHeader("Content-Type", contentType);
        }
        http:Response|http:ClientError reply = otalioClient->execute(method, target, out);
        boolean failed = reply is http:ClientError || (reply is http:Response && reply.statusCode == 502);
        if failed && retriesLeft > 0 {
            retriesLeft -= 1;
            runtime:sleep(httpRetryFrequencySeconds);
            continue;
        }
        return reply;
    }
}

# Otalio's answer for the caller: the status and the body, nothing else of Otalio's headers.
isolated function relay(http:Response reply, string operation, string correlationId) returns http:Response {
    log:printInfo("Otalio answered", correlationId = correlationId, operation = operation, status = reply.statusCode);
    http:Response response = new;
    response.statusCode = reply.statusCode;
    response.setHeader(commons:CORRELATION_HEADER, correlationId);
    if reply.statusCode == 204 {
        return response;
    }
    byte[]|http:ClientError body = reply.getBinaryPayload();
    if body is byte[] && body.length() > 0 {
        string contentType = reply.getContentType();
        response.setBinaryPayload(body, contentType == "" ? "application/json" : contentType);
    }
    return response;
}

# The caller's headers that go on to Otalio (Mule: every header except Authorization), plus the
# correlation id.
isolated function passedOnHeaders(http:Request request, string correlationId) returns map<string[]> {
    map<string[]> headers = {};
    foreach string name in request.getHeaderNames() {
        if core:isForwardedHeader(name) {
            string[]|http:HeaderNotFoundError values = request.getHeaders(name);
            if values is string[] {
                headers[name] = values;
            }
        }
    }
    headers[commons:CORRELATION_HEADER] = [correlationId];
    return headers;
}

// ---------------------------------------------------------------------------------------------
// Sign-in (Mule `accessTokenFlow`)
// ---------------------------------------------------------------------------------------------

# The Authorization header value for the next call.
#
# + rejected - A value Otalio has just refused: it is never returned again ("" for a first call)
# + return - `Bearer <access token>`, or why the service could not sign in
isolated function otalioAuthorization(string rejected) returns string|TokenError {
    lock {
        int now = time:utcNow()[0];
        if core:authorizationUsable(tokenState, now, rejected) {
            return tokenState.authorization;
        }
        if tokenState.refreshToken == "" {
            // the refresh token another copy (or this one before a restart) kept (old: object store)
            [string, int]|error kept = keptRefresh();
            if kept is [string, int] && now < kept[1] {
                tokenState.refreshToken = kept[0];
                tokenState.refreshExpiresAt = kept[1];
            }
        }
        string before = tokenState.refreshToken;
        core:TokenState|TokenError next = signIn(tokenState.clone(), now, rejected != "");
        if next is TokenError {
            return next;
        }
        tokenState = next.clone();
        if next.refreshToken != before && next.refreshToken != "" {
            int ttl = next.refreshExpiresAt - now;
            error? saved = state.put(REFRESH_KEY, next.refreshToken + "|" + next.refreshExpiresAt.toString(), ttl > 0 ? ttl : 0);
            if saved is error {
                log:printWarn("Otalio refresh token not kept in the state store", 'error = saved);
            }
        }
        return next.authorization;
    }
}

# Mule `accessTokenFlow`: with a remembered refresh token, ask for an access token; when Otalio
# refuses it (400), or there is none, log in, remember the new refresh token and take the access
# token of that sign-in.
#
# + state - What the service remembers
# + now - Current second (epoch)
# + afterRefusal - True when Otalio has just refused the access token in use
# + return - What to remember from now on, or why the sign-in failed
isolated function signIn(core:TokenState state, int now, boolean afterRefusal) returns core:TokenState|TokenError {
    core:TokenState next = state.clone();
    json answer = ();
    if core:refreshUsable(state, now) && !afterRefusal {
        [int, json]|TokenError refreshed = signInCall(refreshPath, core:refreshBodyOf(state.refreshToken));
        if refreshed is TokenError {
            return refreshed;
        }
        if refreshed[0] < 400 {
            answer = refreshed[1];
        } else if refreshed[0] != 400 && refreshed[0] != 401 {
            return error TokenError("Otalio did not issue an access token", errorType = commons:BAD_GATEWAY);
        }
    }
    if core:accessTokenOf(answer) is () {
        [int, json]|TokenError login = signInCall(loginPath, core:loginBodyOf(otalioAccount));
        if login is TokenError {
            return login;
        }
        string? refreshToken = core:refreshTokenOf(login[1]);
        if login[0] >= 400 || refreshToken is () {
            log:printError("Otalio refused the service account", status = login[0]);
            return error TokenError("Otalio refused the service's sign-in", errorType = commons:BAD_GATEWAY);
        }
        next.refreshToken = refreshToken;
        next.refreshExpiresAt = now + refreshTokenSeconds;
        answer = login[1];
        if core:accessTokenOf(answer) is () {
            [int, json]|TokenError refreshed = signInCall(refreshPath, core:refreshBodyOf(refreshToken));
            if refreshed is TokenError {
                return refreshed;
            }
            answer = refreshed[1];
        }
    }
    string? accessToken = core:accessTokenOf(answer);
    if accessToken is () {
        return error TokenError("Otalio did not issue an access token", errorType = commons:BAD_GATEWAY);
    }
    next.authorization = core:bearerOf(accessToken);
    next.authorizationExpiresAt = now + core:accessLifetimeOf(answer, accessTokenSeconds);
    return next;
}

isolated function signInCall(string path, json body) returns [int, json]|TokenError {
    map<string> headers = {"Content-Type": "application/json", "Accept": "application/json"};
    http:Response|http:ClientError reply = otalioClient->post(path, body.toJsonString().toBytes(), headers,
        "application/json");
    if reply is http:ClientError {
        return error TokenError("Otalio could not be reached", errorType = commons:errorTypeOfClientError(reply));
    }
    json|http:ClientError answer = reply.getJsonPayload();
    return [reply.statusCode, answer is http:ClientError ? () : answer];
}

isolated function signInFailure(TokenError failure, string operation, string correlationId) returns http:Response {
    string errorType = failure.detail().errorType;
    log:printError("Otalio sign-in failed", correlationId = correlationId, operation = operation,
            errorType = errorType, reason = failure.message());
    return commons:errorResponse(commons:envelopeOf(errorType, failure.message(), correlationId));
}

// ---------------------------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------------------------

# 503 while the Otalio address or the service account is not set; `()` when both are.
isolated function settingsMissing(string correlationId) returns http:Response? {
    if core:isPlaceholderAddress(hTTPRequestOtalioSystemConfig.url) {
        return addressNotSet("hTTPRequestOtalioSystemConfig.url", correlationId);
    }
    string? account = core:missingAccountSetting(otalioAccount);
    if account is string {
        return commons:errorResponse(commons:envelopeOf(commons:SERVICE_UNAVAILABLE,
                        "The Otalio account is not set: " + account, correlationId));
    }
    return ();
}

# 503 for an operation whose backend address was never set.
isolated function addressNotSet(string setting, string correlationId) returns http:Response =>
    commons:errorResponse(commons:envelopeOf(commons:SERVICE_UNAVAILABLE,
                    "The backend address is not set: " + setting, correlationId));

isolated function unreachable(http:ClientError failure, string operation, string correlationId) returns http:Response {
    string errorType = commons:errorTypeOfClientError(failure);
    log:printError("Otalio call failed", correlationId = correlationId, operation = operation, errorType = errorType);
    return commons:errorResponse(commons:envelopeOf(errorType, "Otalio could not be reached", correlationId));
}

isolated function badRequest(string message, string correlationId) returns http:Response =>
    commons:errorResponse(commons:envelopeOf(commons:BAD_REQUEST, message, correlationId));

# The media type without its parameters (e.g. "multipart/form-data" from "multipart/form-data; boundary=..").
isolated function baseMediaType(string contentType) returns string {
    int? semicolon = contentType.indexOf(";");
    return (semicolon is int ? contentType.substring(0, semicolon) : contentType).trim();
}

// object store key of the old application
const string REFRESH_KEY = "refresh_token";

# The refresh token kept in the state store and when it expires.
#
# + return - [refresh token, expiry second], or an error when none is kept
isolated function keptRefresh() returns [string, int]|error {
    string? kept = check state.get(REFRESH_KEY);
    if kept is () {
        return error("none kept");
    }
    int? at = kept.lastIndexOf("|");
    if at is () {
        return error("unreadable");
    }
    return [kept.substring(0, at), check int:fromString(kept.substring(at + 1))];
}
