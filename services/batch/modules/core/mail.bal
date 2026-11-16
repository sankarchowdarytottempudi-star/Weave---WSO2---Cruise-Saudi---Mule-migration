import ballerina/http;
import ballerina/lang.array;
import ballerina/lang.regexp;
import ballerina/log;

// The error e-mail of the old application (Global_Error_Handler -> internal-sys-exp-api-exceptionSub_Flow,
// email-Notification.xml), field by field. It goes to the e-mail system service
// (POST {email-sys-api}/send-email-notification), which sends it through the alerts mailbox.

# Error e-mail settings (old properties `email.toAddress`, `email.ccAddress`, `mule.env`, `app`,
# `httpRequest.internal.emailNotificationPath`).
#
# + enabled - The old application always sent it; false only to silence it on purpose
# + url - Full address of the e-mail system service's send-email-notification operation
# + toAddress - Recipient (old `email.toAddress`)
# + ccAddress - Copy recipient (old `email.ccAddress`)
# + env - Environment name in the subject (old `mule.env`)
# + app - Application name in the subject (old `app`)
# + timeoutSeconds - Time limit of the call
public type MailSettings record {|
    boolean enabled = false;
    string url = "";
    string toAddress = "";
    string ccAddress = "";
    string env = "";
    string app = "seaware-batch-proc-api";
    decimal timeoutSeconds = 30;
|};

# Importance as the old flow set it: High for gateway, server, availability and connectivity
# errors, Low for everything else.
#
# + errorType - Error type identifier (e.g. CONNECTIVITY)
# + return - "High" or "Low"
public isolated function mailImportance(string errorType) returns string =>
    ["BAD_GATEWAY", "INTERNAL_SERVER_ERROR", "SERVICE_UNAVAILABLE", "CONNECTIVITY"].indexOf(errorType) is int ? "High" : "Low";

# The request body the old flow sent to the e-mail system service.
#
# + settings - E-mail settings
# + errorType - Error type identifier ("N/A" when unknown)
# + description - Error description
# + details - Error details (the failing answer)
# + attachment - What the old flow attached (the message being processed), as text
# + return - Request body
public isolated function errorMailBody(MailSettings settings, string errorType, string description, string details,
        string attachment) returns json {
    string content = "<b>Error type :</b> " + errorType + "<br/><b>Description :</b> " + description
        + "<br/><b>Details :</b> " + details
        + "<br/><br/><br/><span style='font-size: 12px;'><b>Important Note:</b><br/>For more information, please refer"
        + " to the MuleSoft application logs or contact the support team.</span>";
    return {
        "message": {
            "subject": settings.env + " - " + settings.app,
            "importance": mailImportance(errorType),
            "body": {"contentType": "HTML", "content": content},
            "toRecipients": [{"emailAddress": {"address": settings.toAddress}}],
            "ccRecipients": [{"emailAddress": {"address": settings.ccAddress}}],
            "attachments": [
                {
                    "@odata.type": "#microsoft.graph.fileAttachment",
                    "name": "batch_errors.txt",
                    "contentType": "text/plain",
                    "contentBytes": array:toBase64(attachment.toBytes())
                }
            ]
        }
    };
}

# Sends the old application's error e-mail. Problems sending it are logged and never stop the job.
public isolated class ErrorMail {
    private final MailSettings & readonly settings;
    private final http:Client? mailClient;

    # + settings - E-mail settings
    # + return - An error when the client cannot be created
    public isolated function init(MailSettings settings) returns error? {
        self.settings = settings.cloneReadOnly();
        if settings.enabled && settings.url != "" {
            http:Client c = check new (settings.url, {timeout: settings.timeoutSeconds});
            self.mailClient = c;
        } else {
            self.mailClient = ();
        }
    }

    # + return - true when e-mails are sent
    public isolated function active() returns boolean => self.mailClient !is ();

    # Sends one error e-mail.
    #
    # + errorType - Error type identifier
    # + description - Error description
    # + details - Error details
    # + attachment - The message being processed, as text
    # + correlationId - Run id (header and log line)
    # + return - "" when sent, otherwise why not
    public isolated function send(string errorType, string description, string details, string attachment,
            string correlationId) returns string {
        http:Client? c = self.mailClient;
        if c is () {
            return "error e-mail switched off";
        }
        json body = errorMailBody(self.settings, errorType, description, details, attachment);
        http:Response|http:ClientError res = c->post("", body, {"correlationId": correlationId});
        if res is http:ClientError {
            log:printError("Error e-mail could not be sent", correlationId = correlationId, reason = res.message());
            return res.message();
        }
        if res.statusCode >= 400 {
            log:printError("Error e-mail was refused", correlationId = correlationId, status = res.statusCode);
            return string `HTTP ${res.statusCode}`;
        }
        return "";
    }
}

# The error type, description and details of an error, as the old e-mail shows them.
#
# + e - The error
# + return - [type, description, details]
public isolated function mailParts(error e) returns [string, string, string] {
    map<anydata> detail = <map<anydata>>e.detail();
    anydata t = detail["errorType"];
    anydata d = detail["details"];
    string errorType = t is string ? t : "N/A";
    if errorType == "N/A" {
        regexp:Groups? g = re `: ([A-Z_]+) \(still failing`.findGroups(e.message());
        if g is regexp:Groups && g.length() > 1 {
            regexp:Span? span = g[1];
            if span is regexp:Span {
                errorType = span.substring();
            }
        }
    }
    return [errorType, e.message(), d is string ? d : "N/A"];
}
