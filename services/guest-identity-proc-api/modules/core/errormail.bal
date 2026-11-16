// The error e-mail (Mule internal-sys-exp-api-exceptionSub_Flow, email-Notification.xml), field by field.

# Importance of the error e-mail, as in this application's Mule flow.
#
# + errorType - Mule error type identifier
# + return - "High" or "Low"
public isolated function mailImportanceOf(string errorType) returns string =>
    ["BAD_GATEWAY", "INTERNAL_SERVER_ERROR", "SERVICE_UNAVAILABLE", "CONNECTIVITY"].indexOf(errorType) != ()
        ? "High" : "Low";

# The error e-mail body (Mule internal-sys-exp-api-exceptionSub_Flow), for the e-mail system API.
#
# + env - Mule `mule.env`
# + app - Mule `app`
# + errorType - Error type identifier
# + description - Error description
# + details - The error body, as text
# + toAddress - Mule `email.toAddress`
# + ccAddress - Mule `email.ccAddress`
# + attachment - Base64 of the failed request's payload (Mule `vars.emailAttachment`)
# + return - The body
public isolated function errorMailOf(string env, string app, string errorType, string description, string details,
        string toAddress, string ccAddress, string attachment) returns json => {
    "message": {
        "subject": env + " - " + app,
        "importance": mailImportanceOf(errorType),
        "body": {
            "contentType": "HTML",
            "content": "<b>Error type :</b> " + errorType + "<br/><b>Description :</b> " + description
                + "<br/><b>Details :</b> " + details
                + "<br/><br/><br/><span style='font-size: 12px;'><b>Important Note:</b><br/>For more information, "
                + "please refer to the MuleSoft application logs or contact the support team.</span>"
        },
        "toRecipients": [{"emailAddress": {"address": toAddress}}],
        "ccRecipients": [{"emailAddress": {"address": ccAddress}}],
        "attachments": [{
            "@odata.type": "#microsoft.graph.fileAttachment",
            "name": "batch_errors.txt",
            "contentType": "text/plain",
            "contentBytes": attachment
        }]
    }
};

# Mule error type of an answer status.
#
# + status - HTTP status
# + return - Error type identifier
public isolated function errorTypeOfStatus(int status) returns string {
    match status {
        400 => {return "BAD_REQUEST";}
        401 => {return "UNAUTHORIZED";}
        403 => {return "FORBIDDEN";}
        404 => {return "NOT_FOUND";}
        405 => {return "METHOD_NOT_ALLOWED";}
        408 => {return "TIMEOUT";}
        429 => {return "TOO_MANY_REQUESTS";}
        502 => {return "BAD_GATEWAY";}
        503 => {return "SERVICE_UNAVAILABLE";}
        504 => {return "TIMEOUT";}
    }
    return status >= 500 ? "INTERNAL_SERVER_ERROR" : "BAD_REQUEST";
}

