import financial_transactions_proc_api.core;

import ballerina/http;
import ballerina/log;

import aroya/integration_commons as commons;

// POST /process-payment: records a paid Telr order as a payment on the Seaware booking.
// Steps, in the order of the Mule flow "process-payment-impl":
//   1. read the order from Telr (Telr system API, `status`);
//   2. find the booking in Seaware and check: booking number matches, Telr says "Paid", the amount
//      is one the booking expects, the order is not already on the booking;
//   3. lock the booking, create the transaction, store (which unlocks), and confirm that the
//      order reference is on the stored booking;
//   4. record the attempt in the payment-attempt audit table (in the background, best effort).
//
// Seaware session:
//   - the caller's agent session from the `X-Seaware-Authorization` header is used when present,
//     the same way the booking operations work. That session is never logged out here.
//   - otherwise the configured service account logs in for this one payment and is logged out at
//     the end (the Mule behaviour). When Seaware says that session is gone, the payment is started
//     again once with a fresh login (`sessionRetryCount`).
//
// Deliberate differences from Mule:
//   - the body is checked (reference characters only) before anything is called;
//   - when the booking number does not match or Telr does not say "Paid", the answer is given
//     without logging in to Seaware (Mule logged in and searched first; same answer);
//   - the call that creates the transaction is never repeated, and a connection failure during
//     it or during the store is answered as "Requires reconciliation";
//   - tokens, bodies and Seaware answers are never written to the log.

const string CUSTOM_ERROR = "CUSTOM-ERROR";
const string SESSION_ERROR = "SESSION";

type StopDetail record {|
    int status;
    string messageType = "";
|};

# A step that ends the payment with a failure answer.
type Stop error<StopDetail>;

# What the caller gets back.
type Outcome record {|
    int status;
    string message;
    string messageType = "";
|};

type Attempt record {|
    core:PaymentInput input;
    string correlationId;
    string? channel;
    string? authorization;
    string? callerSession;
|};

type Session record {|
    string token;
    # True when this service logged in with the service account (and must log out).
    boolean own;
|};

isolated function stop(int status, string message, string messageType = "") returns Stop =>
    error Stop(message, status = status, messageType = messageType);

isolated function outcomeOf(Stop failure) returns Outcome => {
    status: failure.detail().status,
    message: failure.message(),
    messageType: failure.detail().messageType
};

isolated function processPayment(http:Request request) returns http:Response {
    string correlationId = commons:correlationIdOf(request);
    json|http:ClientError payload = request.getJsonPayload();
    if payload is http:ClientError {
        return paymentResponse({status: 400, message: "The request body must be JSON", messageType: "BAD_REQUEST"},
                correlationId);
    }
    core:PaymentInput|error input = core:paymentInputOf(payload);
    if input is error {
        return paymentResponse({status: 400, message: input.message(), messageType: "BAD_REQUEST"}, correlationId);
    }
    foreach [string, string] [setting, address] in [["telrSysApi", telrSysApi.url], ["seawareSysApi", seawareSysApi.url]] {
        if core:isPlaceholderAddress(address) {
            return addressNotSet(setting, correlationId);
        }
    }
    Attempt attempt = {
        input,
        correlationId,
        channel: plainText(commons:headerOf(request, "client_channel")),
        authorization: commons:headerOf(request, "Authorization"),
        callerSession: commons:headerOf(request, "X-Seaware-Authorization")
    };
    Outcome outcome = runPayment(attempt, sessionRetryCount);
    string? errorCode = outcome.status == 200 ? () : failureCodeOf(outcome);
    log:printInfo("process-payment finished", correlationId = correlationId, status = outcome.status,
            errorCode = errorCode ?: "", callerSession = attempt.callerSession is string);
    recordAttempt(attempt, outcome, errorCode);
    return paymentResponse(outcome, correlationId);
}

isolated function paymentResponse(Outcome outcome, string correlationId) returns http:Response {
    map<json> body = {"status": outcome.status == 200 ? "Success" : "Failed", "message": outcome.message};
    if outcome.status != 200 && outcome.messageType != "" {
        // Shape of the Mule error handler's answer.
        body["messageType"] = outcome.messageType;
        body["responseCode"] = outcome.status;
        body["errorDoesNotExist"] = false;
    }
    http:Response response = new;
    response.statusCode = outcome.status;
    response.setHeader(commons:CORRELATION_HEADER, correlationId);
    response.setJsonPayload(body);
    return response;
}

isolated function failureCodeOf(Outcome outcome) returns string {
    string code = core:errorCodeOf(outcome.message);
    return code == "SW_UNKNOWN" && outcome.messageType != "" ? outcome.messageType : code;
}

isolated function runPayment(Attempt attempt, int retriesLeft) returns Outcome {
    // The Seaware login does not depend on the Telr answer, so it starts at the same time
    // (speed only: the decisions below are taken in the old order, Telr first).
    Attempt & readonly frozen = attempt.cloneReadOnly();
    future<Session|Stop> sessionStarted = start openSession(frozen);
    json|Stop telr = telrOrderStatus(attempt);
    if telr is Stop {
        discardSession(frozen, sessionStarted);
        return outcomeOf(telr);
    }
    string bookingNumber = attempt.input.bookingNumber;
    if !core:bookingMatches(telr, bookingNumber) || core:telrStatusTextOf(telr) != "Paid" {
        discardSession(frozen, sessionStarted);
        return {status: 400, message: core:validationOf(telr, bookingNumber, ())};
    }
    Session|Stop|error session = wait sessionStarted;
    if session is error {
        return outcomeOf(session is Stop ? session : stop(502, session.message(), commons:BAD_GATEWAY));
    }
    Outcome|Stop result = payWithSession(attempt, telr, session);
    // The logout does not change the answer; it runs after the answer is on its way
    Session & readonly used = session.cloneReadOnly();
    future<()> _ = start closeSession(frozen, used);
    if result is Outcome {
        return result;
    }
    if result.detail().messageType == SESSION_ERROR {
        if session.own && retriesLeft > 0 {
            log:printWarn("Seaware session was refused; starting the payment again with a fresh login",
                    correlationId = attempt.correlationId);
            return runPayment(attempt, retriesLeft - 1);
        }
        return {status: 400, message: result.message(), messageType: CUSTOM_ERROR};
    }
    return outcomeOf(result);
}

isolated function payWithSession(Attempt attempt, json telr, Session session) returns Outcome|Stop {
    string bookingNumber = attempt.input.bookingNumber;
    string orderRef = attempt.input.orderRef;

    json search = check seawareCall(attempt, session.token, core:searchRequestOf(bookingNumber), "search");
    string validation = core:validationOf(telr, bookingNumber, search);
    if validation != core:VALIDATION_SUCCESS {
        return {status: 400, message: validation};
    }

    _ = check seawareCall(attempt, session.token, core:lockRequestOf(bookingNumber), "lock");

    map<json>|error createRequest = core:transactionCreateRequestOf(telr, paymentSplitOf(attempt), cardMerchant());
    if createRequest is error {
        return stop(400, createRequest.message(), CUSTOM_ERROR);
    }
    _ = check seawareCall(attempt, session.token, createRequest, "transactionCreate", true);
    json stored = check seawareCall(attempt, session.token, core:storeRequestOf(bookingNumber), "store", true);

    if core:storedTransactionFound(stored, orderRef) {
        return {status: 200, message: core:PAYMENT_DONE};
    }
    return {status: 500, message: core:reconciliationMessage(stored, orderRef)};
}

isolated function cardMerchant() returns string => env == "prod" ? "AROYA_PROD" : "AROYA_TEST";

# The component split saved when the Telr session was created. Best effort, as in Mule: when it
# cannot be read the payment is recorded without a split.
isolated function paymentSplitOf(Attempt attempt) returns json[] {
    if !dbConfigured() {
        log:printWarn("Payment context not read: hTTPDBSystemAPIConfig.url is not set",
                correlationId = attempt.correlationId);
        return [];
    }
    json|error rows = dbCall(core:contextSelectOf(attempt.input.orderRef), attempt.correlationId);
    if rows is error {
        log:printError("Payment context was not read", correlationId = attempt.correlationId, reason = rows.message());
        return [];
    }
    return core:extra2Of(rows);
}

// ---------------------------------------------------------------------------------------------
// Telr
// ---------------------------------------------------------------------------------------------

isolated function telrOrderStatus(Attempt attempt) returns json|Stop {
    map<string> headers = {"Content-Type": "application/json", "Accept": "application/json"};
    headers[commons:CORRELATION_HEADER] = attempt.correlationId;
    json body = {"orderRef": attempt.input.orderRef};
    http:Response|http:ClientError reply = telrSysClient->post(telrStatusPath, body.toJsonString().toBytes(), headers);
    if reply is http:ClientError {
        string errorType = commons:errorTypeOfClientError(reply);
        log:printError("Telr status call failed", correlationId = attempt.correlationId, errorType = errorType);
        return stop(commons:statusForErrorType(errorType), "The payment status could not be read from Telr", errorType);
    }
    json|http:ClientError answer = reply.getJsonPayload();
    if reply.statusCode >= 400 || answer is http:ClientError {
        log:printError("Telr status call was refused", correlationId = attempt.correlationId, status = reply.statusCode);
        return stop(502, "The payment status could not be read from Telr", commons:BAD_GATEWAY);
    }
    return answer;
}

// ---------------------------------------------------------------------------------------------
// Seaware
// ---------------------------------------------------------------------------------------------

isolated function openSession(Attempt attempt) returns Session|Stop {
    string? callerSession = attempt.callerSession;
    if callerSession is string {
        return {token: callerSession, own: false};
    }
    if seawareAgent.userName == "" || seawareAgent.password == "" {
        return stop(401, "The Seaware agent session is required in the X-Seaware-Authorization header", "UNAUTHORIZED");
    }
    json answer = check seawareCall(attempt, (), core:loginRequestOf(seawareAgent), "login");
    string? token = core:loginTokenOf(answer);
    if token is () {
        return stop(502, "The Seaware login did not return a session", commons:BAD_GATEWAY);
    }
    return {token, own: true};
}

# A session opened for a payment that stopped before using it: its logout runs in the background.
isolated function discardSession(Attempt & readonly attempt, future<Session|Stop> started) {
    Session|Stop|error session = wait started;
    if session is Session {
        Session & readonly used = session.cloneReadOnly();
        future<()> _ = start closeSession(attempt, used);
    }
}

isolated function closeSession(Attempt attempt, Session session) {
    if session.own {
        json|Stop answer = seawareCall(attempt, session.token, core:logoutRequestOf(), "logout");
        if answer is Stop {
            log:printWarn("Seaware logout failed", correlationId = attempt.correlationId);
        }
    }
}

# One request to the Seaware system API. Never repeated.
#
# + attempt - The payment attempt
# + token - Seaware session, `()` for the login itself
# + body - GraphQL request
# + step - Step name, for the log
# + writes - True for the steps after which the payment may already be on the booking
# + return - Seaware's answer, or the failure that ends the payment
isolated function seawareCall(Attempt attempt, string? token, map<json> body, string step, boolean writes = false)
        returns json|Stop {
    map<string> headers = {"Content-Type": "application/json", "Accept": "application/json"};
    headers[commons:CORRELATION_HEADER] = attempt.correlationId;
    string? authorization = attempt.authorization;
    if authorization is string {
        headers["Authorization"] = authorization;
    }
    if token is string {
        headers["X-Seaware-Authorization"] = token;
    }
    http:Response|http:ClientError reply = seawareSysClient->post(seawarePath, body.toJsonString().toBytes(), headers);
    string orderRef = attempt.input.orderRef;
    if reply is http:ClientError {
        string errorType = commons:errorTypeOfClientError(reply);
        log:printError("Seaware call failed", correlationId = attempt.correlationId, step = step, errorType = errorType);
        if writes {
            return stop(500, "Seaware did not answer while order reference " + orderRef
                    + " was being recorded. Requires reconciliation.", errorType);
        }
        return stop(commons:statusForErrorType(errorType), "Seaware could not be reached", errorType);
    }
    json|http:ClientError answer = reply.getJsonPayload();
    log:printInfo("Seaware answered", correlationId = attempt.correlationId, step = step, status = reply.statusCode);
    if answer is http:ClientError {
        if writes {
            return stop(500, "Seaware gave no readable answer while order reference " + orderRef
                    + " was being recorded. Requires reconciliation.", commons:BAD_GATEWAY);
        }
        return stop(502, "Seaware gave no readable answer", commons:BAD_GATEWAY);
    }
    string? seawareError = core:firstSeawareError(answer);
    if seawareError is string {
        return stop(400, seawareError, core:isSessionError(seawareError) ? SESSION_ERROR : CUSTOM_ERROR);
    }
    if reply.statusCode >= 400 {
        string text = core:textOf(core:fieldOf(answer, "message"));
        return stop(502, text == "" ? "Seaware refused the request" : text, commons:BAD_GATEWAY);
    }
    return answer;
}

// ---------------------------------------------------------------------------------------------
// Payment-attempt audit
// ---------------------------------------------------------------------------------------------

# Header text that is safe to store: letters, digits and a few separators, at most 100 characters.
isolated function plainText(string? value) returns string? {
    if value is () {
        return ();
    }
    string cleaned = re `[^A-Za-z0-9_.:\- ]`.replaceAll(value, "");
    return cleaned.length() > 100 ? cleaned.substring(0, 100) : cleaned;
}

# Writes the attempt to the audit table in the background. Best effort, as in Mule.
isolated function recordAttempt(Attempt attempt, Outcome outcome, string? errorCode) {
    if !dbConfigured() {
        log:printWarn("Payment attempt not recorded: hTTPDBSystemAPIConfig.url is not set",
                correlationId = attempt.correlationId);
        return;
    }
    map<json> & readonly insert = core:auditInsertOf(attempt.input, plainText(attempt.correlationId) ?: "",
            attempt.channel, outcome.status, outcome.message, errorCode).cloneReadOnly();
    future<()> _ = start writeAudit(insert, attempt.correlationId);
}

isolated function writeAudit(map<json> & readonly insert, string correlationId) {
    json|error written = dbCall(insert, correlationId);
    if written is error {
        log:printError("Payment attempt was not recorded", correlationId = correlationId, reason = written.message());
    }
}
