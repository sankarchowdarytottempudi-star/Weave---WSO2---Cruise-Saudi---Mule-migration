import financial_transactions_proc_api.core;

import ballerina/http;
import ballerina/log;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;

// financial-transactions-proc-api on WSO2 (Ballerina). Replaces the Mule project of the same name.
//
// Operations (paths and bodies unchanged for callers):
//   GET  /get-all-checks             -> Otalio system API, operation getArticles, caller's query parameters
//   GET  /getFolio/{accountId}       -> Otalio system API, operation getFolio
//   GET  /pos/{checkId}/check-image  -> Otalio system API, operation checkImage
//   POST /postTransactions           -> Otalio system API, operation postTransactions
//   POST /sessions                   -> Telr system API: create a payment session (payment context saved)
//   POST /status                     -> Telr system API: status of an order
//   POST /process-payment            -> record a paid Telr order on the Seaware booking (payment.bal)
//   POST /payments, /paymentMethods, /adyen/sessions -> Adyen system API
//   GET  /currency-rates             -> exchange rates from the database system API
//   Kafka topic of currency rates    -> stored through the database system API (ratefeed.bal);
//                                       off unless currencyRateListener.enabled = true
//
// Nothing of a request or an answer is written to the log: only operation names, statuses and the
// correlation id.

listener http:Listener httpListener = new (httpPort, timeout = 240);

final http:Client telrSysClient = check commons:newDownstreamClient(telrSysApi);
final http:Client seawareSysClient = check commons:newDownstreamClient(seawareSysApi);
final http:Client otalioSysClient = check commons:newDownstreamClient(otalioSysApi);
final http:Client adyenSysClient = check commons:newDownstreamClient(hTTPRequestAdyenSystemAPI);
final http:Client dbSysClient = check commons:newDownstreamClient(hTTPDBSystemAPIConfig);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    string[] notSet = [];
    foreach [string, string] [name, address] in [
        ["telrSysApi", telrSysApi.url],
        ["seawareSysApi", seawareSysApi.url],
        ["otalioSysApi", otalioSysApi.url],
        ["hTTPRequestAdyenSystemAPI", hTTPRequestAdyenSystemAPI.url],
        ["hTTPDBSystemAPIConfig", hTTPDBSystemAPIConfig.url],
        ["hTTPRequestConfiguration", hTTPRequestConfiguration.url]
    ] {
        if core:isPlaceholderAddress(address) {
            notSet.push(name);
        }
    }
    startCurrencyRateListener();
    log:printInfo("financial-transactions-proc-api starting", env = env, basePath = basePath,
            serviceAccount = seawareAgent.userName != "", addressesNotSet = notSet);
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


    // Mule: GET to the Otalio system API (getArticles) with the caller's query parameters.
    isolated resource function get get\-all\-checks(http:Request request) returns http:Response {
        return callOtalio(request, "getArticles", request.getQueryParams());
    }

    // Mule: GET to the Otalio system API (getFolio) with `shipId` = the id in the path.
    isolated resource function get getFolio/[string accountId](http:Request request) returns http:Response {
        return callOtalio(request, "getFolio", {"shipId": [accountId]});
    }

    // Mule: GET to the Otalio system API (checkImage) with `shipId` = the id in the path.
    isolated resource function get pos/[string checkId]/check\-image(http:Request request) returns http:Response {
        return callOtalio(request, "checkImage", {"shipId": [checkId]});
    }

    // Mule: POST of the body, as received, to the Otalio system API (postTransactions).
    isolated resource function post postTransactions(http:Request request) returns http:Response {
        return callOtalio(request, "postTransactions", {}, true);
    }

    isolated resource function post sessions(http:Request request) returns http:Response {
        return createTelrSession(request);
    }

    isolated resource function post status(http:Request request) returns http:Response {
        return forwardBody(request, telrSysClient, "telrSysApi", telrSysApi.url, telrStatusPath, "status");
    }

    isolated resource function post paymentMethods(http:Request request) returns http:Response {
        return forwardBody(request, adyenSysClient, "hTTPRequestAdyenSystemAPI", hTTPRequestAdyenSystemAPI.url,
                adyenBasePath + "/paymentMethods", "paymentMethods");
    }

    isolated resource function post payments(http:Request request) returns http:Response {
        return forwardBody(request, adyenSysClient, "hTTPRequestAdyenSystemAPI", hTTPRequestAdyenSystemAPI.url,
                adyenBasePath + "/payments", "payments");
    }

    isolated resource function post adyen/sessions(http:Request request) returns http:Response {
        return forwardBody(request, adyenSysClient, "hTTPRequestAdyenSystemAPI", hTTPRequestAdyenSystemAPI.url,
                adyenBasePath + "/sessions", "adyen/sessions");
    }

    isolated resource function get currency\-rates(http:Request request) returns http:Response {
        return currencyRates(request);
    }

    isolated resource function post process\-payment(http:Request request) returns http:Response {
        return processPayment(request);
    }
}

final ErrorRecordedApi apiService = new;

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}

// ---------------------------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------------------------

# 503 for an operation whose backend address was never set.
isolated function addressNotSet(string setting, string correlationId) returns http:Response =>
    commons:errorResponse(commons:envelopeOf(commons:SERVICE_UNAVAILABLE,
                    "The backend address is not set: " + setting + ".url", correlationId));

isolated function unreachable(http:ClientError failure, string backend, string operation, string correlationId)
        returns http:Response {
    string errorType = commons:errorTypeOfClientError(failure);
    log:printError("Backend call failed", correlationId = correlationId, operation = operation, backend = backend,
            errorType = errorType);
    mailHttpError(errorType, "The backend could not be reached: " + backend, failure.message(), correlationId);
    return commons:errorResponse(commons:envelopeOf(errorType, "The backend could not be reached: " + backend,
                    correlationId));
}

isolated function relay(http:Response reply, string operation, string correlationId) returns http:Response {
    log:printInfo("Backend answered", correlationId = correlationId, operation = operation, status = reply.statusCode);
    reply.setHeader(commons:CORRELATION_HEADER, correlationId);
    if reply.statusCode >= 400 {
        // Mule: an HTTP request answered with an error status raises an error -> global handler e-mail
        string|http:ClientError text = reply.getTextPayload();
        mailHttpError(commons:errorTypeOfStatus(reply.statusCode), operation + " answered " + reply.statusCode.toString(),
                text is string ? text : "N/A", correlationId);
    }
    return reply;
}

# The global error handler's e-mail, in the background; never changes the answer.
#
# + errorType - Mule error type identifier
# + description - Mule error.description
# + details - Mule error.exception.errorMessage.payload, as text
# + correlationId - Correlation id
isolated function mailHttpError(string errorType, string description, string details, string correlationId) {
    if !errorMail.enabled {
        return;
    }
    future<()> _ = start sendRateAlert(errorType, description, details == "" ? "N/A" : details, correlationId);
}

# Headers sent to an internal API: content type, correlation id and the caller's Authorization
# and client_channel when present.
isolated function internalHeaders(http:Request request, string correlationId) returns map<string> {
    map<string> headers = {"Content-Type": "application/json", "Accept": "application/json"};
    headers[commons:CORRELATION_HEADER] = correlationId;
    foreach string name in ["Authorization", "client_channel"] {
        string? value = commons:headerOf(request, name);
        if value is string {
            headers[name] = value;
        }
    }
    return headers;
}

# Forwards one request to the Otalio system API.
#
# + request - Caller's request
# + operationName - Otalio operation (`operationName` query parameter)
# + query - Further query parameters
# + withBody - True to POST the caller's body, false to GET
# + return - Otalio system API's answer, as it is
isolated function callOtalio(http:Request request, string operationName, map<string[]> query,
        boolean withBody = false) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    if core:isPlaceholderAddress(otalioSysApi.url) {
        return addressNotSet("otalioSysApi", correlationId);
    }
    string path = core:withQuery(core:withQuery(otalioPath, {"operationName": [operationName]}), query);
    map<string> headers = internalHeaders(request, correlationId);
    http:Response|http:ClientError reply;
    if withBody {
        byte[]|http:ClientError body = request.getBinaryPayload();
        if body is http:ClientError {
            return commons:errorResponse(commons:envelopeOf(commons:BAD_REQUEST, "The request body could not be read",
                            correlationId));
        }
        reply = otalioSysClient->post(path, body, headers);
    } else {
        reply = otalioSysClient->get(path, headers);
    }
    if reply is http:ClientError {
        return unreachable(reply, "otalioSysApi", operationName, correlationId);
    }
    return relay(reply, operationName, correlationId);
}

# Forwards the caller's body, as received, to one backend path and returns the answer as it is.
isolated function forwardBody(http:Request request, http:Client target, string setting, string address, string path,
        string operation) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    if core:isPlaceholderAddress(address) {
        return addressNotSet(setting, correlationId);
    }
    byte[]|http:ClientError body = request.getBinaryPayload();
    if body is http:ClientError {
        return commons:errorResponse(commons:envelopeOf(commons:BAD_REQUEST, "The request body could not be read",
                        correlationId));
    }
    // One attempt only: a payment call is never repeated.
    http:Response|http:ClientError reply = target->post(path, body, internalHeaders(request, correlationId));
    if reply is http:ClientError {
        return unreachable(reply, setting, operation, correlationId);
    }
    return relay(reply, operation, correlationId);
}

# One request to the database system API.
#
# + body - Request (connection key, operation, query, parameters)
# + correlationId - Correlation id
# + return - The answer, or an error when the call failed or was refused
isolated function dbCall(map<json> body, string correlationId) returns json|error {
    map<string> headers = {"Content-Type": "application/json", "Accept": "application/json"};
    headers[commons:CORRELATION_HEADER] = correlationId;
    http:Response|http:ClientError reply = dbSysClient->post(dbSystemPath, body.toJsonString().toBytes(), headers);
    if reply is http:ClientError {
        return error("database system API call failed: " + commons:errorTypeOfClientError(reply));
    }
    if reply.statusCode >= 400 {
        return error("database system API answered " + reply.statusCode.toString());
    }
    json|http:ClientError answer = reply.getJsonPayload();
    if answer is http:ClientError {
        return error("database system API answer is not JSON");
    }
    return answer;
}

isolated function dbConfigured() returns boolean => !core:isPlaceholderAddress(hTTPDBSystemAPIConfig.url);

// ---------------------------------------------------------------------------------------------
// POST /sessions
// ---------------------------------------------------------------------------------------------

// Mule: save the payment context (the request, keyed by cart id), ask the Telr system API for a
// session, then write Telr's order reference on the saved context. Both database steps are
// best effort, as in Mule: a failure is logged and the session is still created.
isolated function createTelrSession(http:Request request) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    if core:isPlaceholderAddress(telrSysApi.url) {
        return addressNotSet("telrSysApi", correlationId);
    }
    json|http:ClientError payload = request.getJsonPayload();
    if payload is http:ClientError {
        return commons:errorResponse(commons:envelopeOf(commons:BAD_REQUEST, "The request body must be JSON",
                        correlationId));
    }
    json contextId = ();
    if dbConfigured() {
        json|error inserted = dbCall(core:contextInsertOf(core:sessionDocumentOf(payload)), correlationId);
        if inserted is error {
            log:printError("Payment context was not saved", correlationId = correlationId, reason = inserted.message());
        } else {
            contextId = core:contextIdOf(inserted);
        }
    } else {
        log:printWarn("Payment context not saved: hTTPDBSystemAPIConfig.url is not set", correlationId = correlationId);
    }

    // One attempt only: a payment call is never repeated.
    http:Response|http:ClientError reply = telrSysClient->post(telrSessionsPath, payload.toJsonString().toBytes(),
        internalHeaders(request, correlationId));
    if reply is http:ClientError {
        return unreachable(reply, "telrSysApi", "sessions", correlationId);
    }
    byte[]|http:ClientError answer = reply.getBinaryPayload();
    http:Response response = new;
    response.statusCode = reply.statusCode;
    response.setHeader(commons:CORRELATION_HEADER, correlationId);
    if answer is byte[] && answer.length() > 0 {
        response.setBinaryPayload(answer, "application/json");
        if contextId != () && reply.statusCode < 400 {
            string|error text = string:fromBytes(answer);
            json telrAnswer = text is string ? core:jsonOfText(text) : ();
            json|error updated = dbCall(core:contextUpdateOf(contextId, telrAnswer), correlationId);
            if updated is error {
                log:printError("Payment context was not updated", correlationId = correlationId,
                        reason = updated.message());
            }
        }
    }
    log:printInfo("Backend answered", correlationId = correlationId, operation = "sessions",
            status = reply.statusCode, contextSaved = contextId != ());
    return response;
}

// ---------------------------------------------------------------------------------------------
// GET /currency-rates
// ---------------------------------------------------------------------------------------------

isolated function currencyRates(http:Request request) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    core:RatesParams params = core:ratesParamsOf(request.getQueryParams());
    error? invalid = core:checkRatesParams(params);
    if invalid is error {
        return commons:errorResponse(commons:envelopeOf(commons:BAD_REQUEST, invalid.message(), correlationId));
    }
    if !dbConfigured() {
        return addressNotSet("hTTPDBSystemAPIConfig", correlationId);
    }
    json|error rows = dbCall(core:ratesQueryOf(params), correlationId);
    if rows is error {
        log:printError("Currency rates could not be read", correlationId = correlationId, reason = rows.message());
        return commons:errorResponse(commons:envelopeOf(commons:BAD_GATEWAY, "The currency rates could not be read",
                        correlationId));
    }
    http:Response response = new;
    response.statusCode = 200;
    response.setHeader(commons:CORRELATION_HEADER, correlationId);
    response.setJsonPayload(core:ratesResponseOf(rows, params));
    return response;
}
