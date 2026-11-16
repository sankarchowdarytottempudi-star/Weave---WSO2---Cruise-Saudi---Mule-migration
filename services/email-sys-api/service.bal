import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerinax/prometheus as _;

import aroya/email_sys_api.core;
import aroya/integration_commons as commons;

// email-sys-api on WSO2 (Ballerina), migrated from cs-repo-email-sys-api-prod (mule4).
//
// One operation, three ways to send, chosen exactly as the old API chose:
//   header `provider: exchange`   -> the mail server of Email_SMTP_Zepto (one-time codes, welcome and summary e-mails)
//   otherwise, target `shore`     -> the mail provider's HTTPS API with an application token
//   otherwise, target `ship`      -> the ship's mail server, fixed recipients
//
// The answer is 200 only when the mail server or the provider has taken the message. Anything
// else (account not entered, login refused, redirect, time-out) is an error, so a caller never
// reports "sent" for an e-mail that was not sent.
//
// Deliberate differences from the old API:
//   - The access token is asked for when a message needs one and kept for tokenMinutes; there is
//     no timer job.
//   - A request without `to`, `subject` or `body` is answered with 400 (the old API failed with 500).
//   - A 401 from the provider is repeated once with a new token.
//   - On a ship, the first attachment is decoded and attached as a file under its own name.
//   - Addresses, subjects and bodies are never logged (the old API logged the whole request).

listener http:Listener httpListener = new (httpPort);

function init() returns error? {
    log:printInfo("state store", keptIn = state.location());
    check httpListener.attach(apiService, basePath);
    log:printInfo("email-sys-api starting", env = env, basePath = basePath, deploymentTarget = deploymentTarget,
            exchange = stateOf(exchangeMissing()), shore = stateOf(shoreMissing()), ship = stateOf(shipMissing()));
    foreach string url in [sendEmailHTTPRequestConfig.url, tokenHTTPRequestConfig.url] {
        if core:shouldBeHttps(url) {
            log:printWarn("A provider address starts with http, not https. Such an address answers with a redirect "
                    + "and sends nothing; the service reports that as an error.");
        }
    }
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

    # Source: POST /email-sys-api/v1/send-email-notification (post:\send-email-notification:application\json:email-system-api-config)
    isolated resource function post send\-email\-notification(http:Request request) returns http:Response {
        string correlationId = commons:correlationIdOf(request);
        decimal began = time:monotonicNow();
        json|http:ClientError payload = request.getJsonPayload();
        string way = (commons:headerOf(request, "provider") ?: "") == "exchange" ? "exchange" : deploymentTarget;
        Outcome outcome;
        if payload is http:ClientError {
            outcome = notSent(commons:BAD_REQUEST, "Bad request");
        } else if way == "exchange" {
            outcome = sendExchange(payload, correlationId);
        } else if way == "shore" {
            outcome = sendShore(payload, correlationId);
        } else if way == "ship" {
            outcome = sendShip(payload, correlationId);
        } else {
            // Mule: APP:INVALID_ENV
            outcome = notSent(commons:INTERNAL_SERVER_ERROR, "Unsupported env: " + way);
        }
        if outcome.sent {
            log:printInfo("E-mail sent", correlationId = correlationId, way = way, recipients = outcome.recipients,
                    attempts = outcome.attempts, durationMs = millisSince(began));
            http:Response response = new;
            response.statusCode = 200;
            response.setJsonPayload({message: "Email sent."});
            response.setHeader(commons:CORRELATION_HEADER, correlationId);
            return response;
        }
        log:printError("E-mail not sent", correlationId = correlationId, way = way, errorType = outcome.errorType,
                reason = outcome.message, detail = outcome.detail, attempts = outcome.attempts,
                durationMs = millisSince(began));
        return commons:errorResponse(commons:envelopeOf(outcome.errorType, outcome.message, correlationId,
                outcome.status, outcome.detail == "" ? () : outcome.detail));
    }
}

final ErrorRecordedApi apiService = new;

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};

    # Which ways of sending have their settings. Names only, never a value.
    #
    # + return - Per way: "ready", or the names of the settings that have no value
    isolated resource function get mail() returns json => {
        deploymentTarget,
        exchange: stateOf(exchangeMissing()),
        shore: stateOf(shoreMissing()),
        ship: stateOf(shipMissing())
    };
}

isolated function stateOf(string[] missing) returns string =>
    missing.length() == 0 ? "ready" : "not set: " + string:'join(", ", ...missing);

isolated function millisSince(decimal began) returns int => <int>((time:monotonicNow() - began) * 1000);
