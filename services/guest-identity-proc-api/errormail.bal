import guest_identity_proc_api.core;

import ballerina/http;
import ballerina/lang.array;
import ballerina/log;
import aroya/integration_commons as commons;

# Error e-mail through the e-mail system API (Mule Global_Error_Handler -> internal-sys-exp-api-exceptionSub_Flow).
#
# + enabled - Switch (off by default: switching on sends real e-mails to these recipients)
# + url - Address of the e-mail system API (Mule HTTP_Request_configuration_internal)
# + path - Mule httpRequest.internal.emailNotificationPath
# + toAddress - Mule email.toAddress
# + ccAddress - Mule email.ccAddress
# + app - Mule app (subject)
# + env - Mule mule.env (subject); empty = the service's env setting
# + timeoutSeconds - Time limit of the e-mail call
type ErrorMailSettings record {|
    boolean enabled = false;
    string url = "";
    string path = "/email-sys-api/v1/send-email-notification";
    string toAddress = "";
    string ccAddress = "";
    string app = "guest-identity-proc-api";
    string env = "";
    decimal timeoutSeconds = 30;
|};

configurable ErrorMailSettings errorMail = {};

final http:Client? mailClient = mailClientOf();

function mailClientOf() returns http:Client? {
    if !errorMail.enabled || core:isPlaceholderAddress(errorMail.url) {
        return ();
    }
    http:Client|http:ClientError made = new (errorMail.url, {timeout: errorMail.timeoutSeconds});
    if made is http:ClientError {
        log:printError("Error e-mails are switched on but the client could not be made", 'error = made);
        return ();
    }
    return made;
}

# Sends the error e-mail of a failed operation in the background. Never changes the answer.
#
# + operation - Operation name
# + status - Status answered
# + body - Error body answered
# + correlationId - Correlation id
isolated function mailError(string operation, int status, json body, string correlationId) {
    if mailClient is () || status < 500 {
        return;
    }
    string description = body is map<json> && body["message"] is string ? <string>body["message"]
        : operation + " answered " + status.toString();
    string details = body.toJsonString();
    future<()> _ = start sendErrorMail(core:errorTypeOfStatus(status), description, details, correlationId);
}

isolated function sendErrorMail(string errorType, string description, string details, string correlationId) {
    http:Client? mails = mailClient;
    if mails is () {
        return;
    }
    json body = core:errorMailOf(errorMail.env == "" ? env : errorMail.env, errorMail.app, errorType, description,
            details, errorMail.toAddress, errorMail.ccAddress, array:toBase64(details.toBytes()));
    http:Response|http:ClientError sent = mails->post(errorMail.path, body, {[commons:CORRELATION_HEADER]: correlationId});
    if sent is http:ClientError {
        log:printWarn("Error e-mail not sent", correlationId = correlationId, reason = sent.message());
    } else if sent.statusCode >= 300 {
        log:printWarn("Error e-mail refused", correlationId = correlationId, status = sent.statusCode);
    }
}
