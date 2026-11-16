// The error e-mail of cms-proc-api (Mule cms-proc-api-exception.xml, exceptionSub_Flow), field by field.

# Importance as in this application's Mule flow.
#
# + errorType - Mule error type identifier
# + return - "High" or "Low"
public isolated function mailImportanceOf(string errorType) returns string =>
    ["BAD_GATEWAY", "INTERNAL_SERVER_ERROR", "SERVICE_UNAVAILABLE", "CONNECTIVITY"].indexOf(errorType) != ()
        ? "High" : "Low";

# The error e-mail body for the e-mail system API.
#
# + apiName - Mule: the application named in the failing component
# + errorType - Error type identifier
# + description - Error description
# + details - The error body, as text
# + toAddress - Mule email.toAddress
# + ccAddress - Mule email.ccAddress
# + saveToSentItems - Mule email.saveType
# + return - The body
public isolated function errorMailOf(string apiName, string errorType, string description, string details,
        string toAddress, string ccAddress, boolean saveToSentItems) returns json {
    string importance = mailImportanceOf(errorType);
    return {
        "message": {
            "subject": importance == "High" ? "⚠️" + apiName : apiName,
            "importance": importance,
            "body": {
                "contentType": "HTML",
                "content": "<b>Error type :</b> " + errorType + "<br/><b>Description :</b> " + description
                    + "<br/><b>Details :</b> " + details
                    + "<br/><br/><br/><span style='font-size: 12px;'><b>Important Note:</b><br/>For more information, "
                    + "please refer to the MuleSoft application logs or contact the support team.</span>"
            },
            "toRecipients": [{"emailAddress": {"address": toAddress}}],
            "ccRecipients": [{"emailAddress": {"address": ccAddress}}]
        },
        "saveToSentItems": saveToSentItems
    };
}
