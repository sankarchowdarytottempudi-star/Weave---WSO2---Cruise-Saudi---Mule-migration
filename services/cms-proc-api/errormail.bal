import cms_proc_api.core;

import ballerina/http;
import ballerina/log;
import aroya/integration_commons as commons;

# Error e-mail (Mule Global_Error_Handler -> exceptionSub_Flow, connection HTTP_Request_Email).
#
# + enabled - Switch (off by default: switching on sends real e-mails to these recipients)
# + url - Mule email.host / email.port (https)
# + path - Mule email.path
# + toAddress - Mule email.toAddress
# + ccAddress - Mule email.ccAddress
# + saveToSentItems - Mule email.saveType
# + apiName - Name in the subject
# + timeoutSeconds - Mule email.timeout
type ErrorMailSettings record {|
    boolean enabled = false;
    string url = "";
    string path = "";
    string toAddress = "";
    string ccAddress = "";
    boolean saveToSentItems = false;
    string apiName = "cms-proc-api";
    decimal timeoutSeconds = 30;
|};

configurable ErrorMailSettings errorMail = {};

final http:Client? mailClient = mailClientOf();

function mailClientOf() returns http:Client? {
    if !errorMail.enabled || errorMail.url == "" || errorMail.url.includes("//localhost") {
        return ();
    }
    http:Client|http:ClientError made = new (errorMail.url, {timeout: errorMail.timeoutSeconds});
    if made is http:ClientError {
        log:printError("Error e-mails are switched on but the client could not be made", 'error = made);
        return ();
    }
    return made;
}

# Sends the error e-mail of a failed call in the background. Never changes the answer.
#
# + errorType - Error type identifier
# + description - Error description
# + details - Error body as text
# + correlationId - Correlation id
isolated function mailError(string errorType, string description, string details, string correlationId) {
    if mailClient is () {
        return;
    }
    future<()> _ = start sendErrorMail(errorType, description, details, correlationId);
}

isolated function sendErrorMail(string errorType, string description, string details, string correlationId) {
    http:Client? mails = mailClient;
    if mails is () {
        return;
    }
    json body = core:errorMailOf(errorMail.apiName, errorType, description, details, errorMail.toAddress,
            errorMail.ccAddress, errorMail.saveToSentItems);
    http:Response|http:ClientError sent = mails->post(errorMail.path, body, {[commons:CORRELATION_HEADER]: correlationId});
    if sent is http:ClientError {
        log:printWarn("Error e-mail not sent", correlationId = correlationId, reason = sent.message());
    } else if sent.statusCode >= 300 {
        log:printWarn("Error e-mail refused", correlationId = correlationId, status = sent.statusCode);
    }
}
