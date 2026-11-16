import zoho_sys_api.core;

import ballerina/http;
import ballerina/log;
import ballerina/mime;
import ballerina/time;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;

// zoho-sys-api on WSO2 (Ballerina). Replaces the Mule project of the same name.
//
// Contract (unchanged for callers):
//   GET | POST | PUT {basePath}/zoho/{module}[/{record id}]
//       -> the same method on Zoho CRM at /crm/v2/{module}[/{record id}], with the caller's query
//          parameters and (POST, PUT) the caller's body. Zoho's answer and status are returned.
//   Header `zohoPath: /crm/v2/...` -> that Zoho path is used instead of the one built from the address.
//   A Zoho path that ends in /photo (POST, PUT) -> body { "file": "<base64 photo>" } is sent to Zoho
//          as a file upload (form part `file`, photo.jpg, image/jpeg).
//
// The service signs in to Zoho itself: it asks the Zoho accounts service for an access token with
// the configured OAuth client, reuses the token for `tokenMinutes`, and when Zoho answers
// "invalid oauth token" it asks for a new one and repeats the call (at most `unauthorizedRetryCount`
// times). Callers never send Zoho credentials.
//
// An answer of 400 or above from Zoho is returned with Zoho's status and the body
//   { timestamp, statusCode, message, correlationId, error, targetError: <Zoho's answer> }
// as the Mule error handler did.
//
// Deliberate differences from Mule:
//   - nothing of a request, an answer or a token is written to the log: only the method, the
//     status and the correlation id (the Mule loggers wrote payloads);
//   - error and audit records are not published to Kafka (both switches were off in the uploaded
//     settings); the same events are log lines;
//   - Zoho's 204 "no content" is returned as 204 without a body (Mule set the body to [] with
//     status 204, and a 204 answer carries no body on the wire);
//   - a request that names no Zoho path is refused with 400 instead of being sent to Zoho's root;
//   - a message about a failed connection never contains an address.

listener http:Listener httpListener = new (httpPort, timeout = 150);

final http:Client zohoAccountsClient = check commons:newDownstreamClient(hTTPRequestZohoAccessConfig);
final http:Client zohoCrmClient = check commons:newDownstreamClient(zohoCRMAPIConfig);

# The access token in use and the second (epoch) until which it is reused.
type TokenState record {|
    string token;
    int expiresAt;
|};

# Why no access token could be obtained.
type TokenError error<record {|string errorType;|}>;

isolated TokenState tokenState = {token: "", expiresAt: 0};

function init() returns error? {
    log:printInfo("state store", keptIn = state.location());
    check httpListener.attach(apiService, basePath);
    string[] notSet = [];
    if core:isPlaceholderAddress(hTTPRequestZohoAccessConfig.url) {
        notSet.push("hTTPRequestZohoAccessConfig.url");
    }
    if core:isPlaceholderAddress(zohoCRMAPIConfig.url) {
        notSet.push("zohoCRMAPIConfig.url");
    }
    string? account = core:missingAccountSetting(zohoAccount);
    if account is string {
        notSet.push(account);
    }
    log:printInfo("zoho-sys-api starting", env = env, basePath = basePath, settingsNotSet = notSet);
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


    // Mule listener `v1/zoho/*` also takes /zoho itself: callers (the Seaware and Otalio sync jobs)
    // call /zoho and name the CRM path in the zohoPath header.
    isolated resource function get zoho(http:Request request) returns http:Response {
        return callZoho(request, "GET", []);
    }

    isolated resource function post zoho(http:Request request) returns http:Response {
        return callZoho(request, "POST", []);
    }

    isolated resource function put zoho(http:Request request) returns http:Response {
        return callZoho(request, "PUT", []);
    }

    isolated resource function get zoho/[string... path](http:Request request) returns http:Response {
        return callZoho(request, "GET", path);
    }

    isolated resource function post zoho/[string... path](http:Request request) returns http:Response {
        return callZoho(request, "POST", path);
    }

    isolated resource function put zoho/[string... path](http:Request request) returns http:Response {
        return callZoho(request, "PUT", path);
    }
}

final ErrorRecordedApi apiService = new;

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}

// ---------------------------------------------------------------------------------------------
// The one operation: forward a request to Zoho CRM
// ---------------------------------------------------------------------------------------------

isolated function callZoho(http:Request request, string method, string[] segments) returns http:Response {
    string correlationId = correlationOf(request);
    if core:isPlaceholderAddress(zohoCRMAPIConfig.url) {
        return addressNotSet("zohoCRMAPIConfig.url", correlationId);
    }
    if core:isPlaceholderAddress(hTTPRequestZohoAccessConfig.url) {
        return addressNotSet("hTTPRequestZohoAccessConfig.url", correlationId);
    }
    string? account = core:missingAccountSetting(zohoAccount);
    if account is string {
        return commons:errorResponse(commons:envelopeOf(commons:SERVICE_UNAVAILABLE,
                        "The Zoho account is not set: " + account, correlationId));
    }

    string zohoPath = core:zohoPathOf(commons:headerOf(request, "zohoPath"), segments, crmPathPrefix);
    if zohoPath == "" {
        return badRequest("The request names no Zoho path: call /zoho/{module}[/{record id}] or send the zohoPath header",
                correlationId);
    }
    if !core:isSafePath(zohoPath) {
        return badRequest("The Zoho path is not valid", correlationId);
    }
    string target = core:withQuery(zohoPath, request.getQueryParams());

    byte[] body = [];
    byte[]? photo = ();
    if method != "GET" {
        byte[]|http:ClientError received = request.getBinaryPayload();
        if received is byte[] {
            body = received;
        } else if request.hasHeader("Content-Length") && request.getHeader("Content-Length") != "0" {
            return badRequest("The request body could not be read", correlationId);
        }
        if core:isPhotoPath(zohoPath) {
            byte[]|error bytes = core:photoBytesOf(core:answerOf(body));
            if bytes is error {
                return badRequest(bytes.message(), correlationId);
            }
            photo = bytes;
        }
    }

    string|TokenError token = zohoToken("");
    int attempt = 0;
    while attempt <= unauthorizedRetryCount {
        if token is TokenError {
            return tokenFailure(token, correlationId);
        }
        decimal sentAt = time:monotonicNow();
        http:Response|http:ClientError reply = sendToZoho(method, target, token, body, photo);
        int zohoMs = <int>((time:monotonicNow() - sentAt) * 1000);
        if reply is http:ClientError {
            string errorType = commons:errorTypeOfClientError(reply);
            log:printError("Zoho call failed", correlationId = correlationId, method = method, errorType = errorType);
            return commons:errorResponse(commons:envelopeOf(errorType, "Zoho could not be reached", correlationId));
        }
        if reply.statusCode < 400 {
            log:printInfo("Zoho answered", correlationId = correlationId, method = method, status = reply.statusCode,
                    upload = photo is byte[], tokenRenewals = attempt, durationMs = zohoMs,
                    module = core:moduleOf(zohoPath));
            return answerOf(reply, correlationId);
        }
        byte[]|http:ClientError raw = reply.getBinaryPayload();
        json targetError = core:answerOf(raw is byte[] ? raw : []);
        if core:isExpiredTokenAnswer(targetError) && attempt < unauthorizedRetryCount {
            // Mule: "invalid oauth token" -> a new token, then the same call again.
            log:printWarn("Zoho refused the access token; asking for a new one", correlationId = correlationId,
                    attempt = attempt + 1);
            token = zohoToken(token);
            attempt += 1;
            continue;
        }
        log:printError("Zoho answered with an error", correlationId = correlationId, method = method,
                status = reply.statusCode, errorType = core:errorTypeOfStatus(reply.statusCode), durationMs = zohoMs);
        return commons:errorResponse(commons:envelopeOf(core:errorTypeOfStatus(reply.statusCode),
                        core:errorMessageOf(targetError, reply.statusCode), correlationId, reply.statusCode, targetError));
    }
    return commons:errorResponse(commons:envelopeOf(commons:UNAUTHORIZED, "Zoho refused the access token",
                    correlationId));
}

# One call to Zoho CRM.
#
# + method - GET, POST or PUT
# + target - Zoho path with the query parameters
# + token - Access token
# + body - Caller's body (POST, PUT)
# + photo - Bytes of the photo for an upload, `()` for any other call
# + return - Zoho's answer
isolated function sendToZoho(string method, string target, string token, byte[] body, byte[]? photo)
        returns http:Response|http:ClientError {
    string authorization = core:authorizationOf(token);
    if method == "GET" {
        return zohoCrmClient->get(target, {"Authorization": authorization, "Content-Type": "application/json"});
    }
    http:Request out = new;
    out.setHeader("Authorization", authorization);
    if photo is byte[] {
        // Mule: multipart/form-data with one part `file` (photo.jpg, image/jpeg) and only the
        // Authorization header.
        mime:Entity part = new;
        mime:ContentDisposition disposition = mime:getContentDispositionObject(
                "form-data; name=\"file\"; filename=\"photo.jpg\"");
        part.setContentDisposition(disposition);
        part.setByteArray(photo, "image/jpeg");
        out.setBodyParts([part], mime:MULTIPART_FORM_DATA);
    } else {
        out.setBinaryPayload(body, "application/json");
    }
    return zohoCrmClient->execute(method, target, out);
}

# Zoho's answer for the caller: the status and the body, nothing else of Zoho's headers.
isolated function answerOf(http:Response reply, string correlationId) returns http:Response {
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

// ---------------------------------------------------------------------------------------------
// Access token (Mule sub-flow `Get_Zoho_token`: object store, 55 minutes)
// ---------------------------------------------------------------------------------------------

# The access token to use for the next call.
#
# + rejected - A token Zoho has just refused: it is never returned again ("" for a first call)
# + return - Access token, or why none could be obtained
isolated function zohoToken(string rejected) returns string|TokenError {
    lock {
        int now = time:utcNow()[0];
        if core:tokenUsable(tokenState.token, tokenState.expiresAt, now, rejected) {
            return tokenState.token;
        }
        // another copy of the service may have a token already (old: object store, shared)
        TokenState|error kept = keptToken();
        if kept is TokenState && core:tokenUsable(kept.token, kept.expiresAt, now, rejected) {
            tokenState = {token: kept.token, expiresAt: kept.expiresAt};
            return kept.token;
        }
        string|TokenError issued = requestToken();
        if issued is TokenError {
            return issued;
        }
        tokenState = {token: issued, expiresAt: now + tokenMinutes * 60};
        error? saved = state.put(ZOHO_TOKEN_KEY, issued + "|" + tokenState.expiresAt.toString(), tokenMinutes * 60);
        if saved is error {
            log:printWarn("Zoho access token not kept in the state store", 'error = saved);
        }
        return issued;
    }
}

isolated function requestToken() returns string|TokenError {
    map<string> headers = {"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"};
    http:Response|http:ClientError reply = zohoAccountsClient->post(tokenPath,
        core:tokenFormOf(zohoAccount).toBytes(), headers, "application/x-www-form-urlencoded");
    if reply is http:ClientError {
        return error TokenError("The Zoho accounts service could not be reached",
            errorType = commons:errorTypeOfClientError(reply));
    }
    json|http:ClientError answer = reply.getJsonPayload();
    string|error token = core:accessTokenOf(answer is http:ClientError ? () : answer);
    if token is error {
        return error TokenError(token.message(), errorType = commons:BAD_GATEWAY);
    }
    log:printInfo("Zoho access token issued", status = reply.statusCode);
    return token;
}

isolated function tokenFailure(TokenError failure, string correlationId) returns http:Response {
    string errorType = failure.detail().errorType;
    log:printError("No Zoho access token", correlationId = correlationId, errorType = errorType,
            reason = failure.message());
    return commons:errorResponse(commons:envelopeOf(errorType, failure.message(), correlationId));
}

// ---------------------------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------------------------

# The request's correlation id: header `correlationId`, else `correaltionId` (the spelling the
# Mule flow read), else a new one.
isolated function correlationOf(http:Request request) returns string {
    string? misspelt = commons:headerOf(request, "correaltionId");
    if commons:headerOf(request, commons:CORRELATION_HEADER) is () && misspelt is string {
        return misspelt;
    }
    return commons:correlationIdOf(request);
}

# 503 for an operation whose backend address was never set.
isolated function addressNotSet(string setting, string correlationId) returns http:Response =>
    commons:errorResponse(commons:envelopeOf(commons:SERVICE_UNAVAILABLE,
                    "The backend address is not set: " + setting, correlationId));

isolated function badRequest(string message, string correlationId) returns http:Response =>
    commons:errorResponse(commons:envelopeOf(commons:BAD_REQUEST, message, correlationId));

// object store key of the old application
const string ZOHO_TOKEN_KEY = "zohoAccessToken";

# The token another copy of the service (or this one before a restart) has kept, if any.
#
# + return - The kept token and when it expires, or an error when none is kept
isolated function keptToken() returns TokenState|error {
    string? kept = check state.get(ZOHO_TOKEN_KEY);
    if kept is () {
        return error("none kept");
    }
    int? at = kept.lastIndexOf("|");
    if at is () {
        return error("unreadable");
    }
    return {token: kept.substring(0, at), expiresAt: check int:fromString(kept.substring(at + 1))};
}
