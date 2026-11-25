import ballerina/http;
import ballerina/log;

// Error e-mail, replacing exception-email-sub-flow.xml. Same message shape, sent through
// email-sys-api; same importance rules.

# E-mail notification settings.
#
# + enabled - Mule `email.enabled`
# + url - email-sys-api endpoint (Mule `email.api`)
# + toRecipients - Mule `email.toRecipients`
# + ccRecipients - Mule `email.ccRecipients`
# + timeoutSeconds - Mule `resilience.supportRequestTimeoutMs` / 1000
public type NotifySettings record {|
    boolean enabled = false;
    string url = "";
    string[] toRecipients = [];
    string[] ccRecipients = [];
    decimal timeoutSeconds = 5;
|};

# Importance of an error e-mail (Mule `importanceLevel`).
#
# + errorType - The error type
# + return - `High`, `Normal` or `Low`
public isolated function importanceOf(string errorType) returns string {
    if errorType == "RETRY_EXHAUSTED" || errorType == INTERNAL_SERVER_ERROR || errorType == SERVICE_UNAVAILABLE {
        return "High";
    }
    if errorType == NOT_FOUND || errorType == BAD_REQUEST {
        return "Low";
    }
    return "Normal";
}

# The email-sys-api request body.
#
# + apiName - Subject (the failing API)
# + errorType - Error type
# + description - Error description
# + details - More detail
# + settings - Recipients
# + return - The JSON body
public isolated function emailBodyOf(string apiName, string errorType, string description, string details,
        NotifySettings settings) returns json {
    json[] to = from string address in settings.toRecipients
        select {emailAddress: {address}};
    json[] cc = from string address in settings.ccRecipients
        select {emailAddress: {address}};
    string content = string `<b>Error type :</b> ${errorType}<br/><b>Description :</b> ${description}`
        + string `<br/><b>Details :</b> ${details}<br/><br/><br/><span style='font-size: 12px;'>`
        + "<b>Important Note:</b><br/>For more information, please refer to the application logs "
        + "(trace by correlation id) or contact the support team.</span>";
    return {
        message: {
            subject: apiName,
            importance: importanceOf(errorType),
            body: {contentType: "HTML", content},
            toRecipients: to,
            ccRecipients: cc
        }
    };
}

# Sends error e-mails. Never fails the request that triggered it.
public isolated class ErrorNotifier {
    private final NotifySettings & readonly settings;
    private final http:Client? emailClient;

    # + settings - Notification settings
    # + return - An error if the client cannot be created
    public isolated function init(NotifySettings settings) returns error? {
        self.settings = settings.cloneReadOnly();
        if settings.enabled && settings.url != "" {
            http:Client emailClient = check new (settings.url, {timeout: settings.timeoutSeconds});
            self.emailClient = emailClient;
        } else {
            self.emailClient = ();
        }
    }

    # Sends one e-mail for a failed request.
    #
    # + apiName - The failing API
    # + errorType - Error type
    # + description - Error description
    # + details - More detail
    # + correlationId - For the log line
    public isolated function notify(string apiName, string errorType, string description, string details,
            string correlationId) {
        http:Client? emailClient = self.emailClient;
        if emailClient is () {
            return;
        }
        json body = emailBodyOf(apiName, errorType, description, details, self.settings);
        http:Response|http:ClientError sent = emailClient->post("", body, {correlationId});
        if sent is http:ClientError {
            log:printError("Error e-mail failed", correlationId = correlationId, 'error = sent);
        }
    }
}
