import ballerina/email;
import ballerina/http;
import ballerina/lang.array;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/mime;
import ballerina/time;
import ballerina/url;

import aroya/email_sys_api.core;
import aroya/integration_commons as commons;

// Sending: the three sub-flows of the old API.

# What became of one request.
#
# + sent - True only when the mail server or the provider took the message
# + recipients - How many addresses the message went to (never the addresses)
# + attempts - How many times the provider was called
# + errorType - Error type for the answer when not sent
# + message - Summary for the caller
# + detail - The server's own words, without addresses
# + status - The provider's HTTP status, when there was one
type Outcome record {|
    boolean sent;
    int recipients = 0;
    int attempts = 1;
    string errorType = "";
    string message = "";
    string detail = "";
    int? status = ();
|};

isolated function notSent(string errorType, string message, string detail = "", int? status = (), int attempts = 1)
        returns Outcome => {sent: false, errorType, message, detail: core:withoutAddresses(detail), status, attempts};

isolated function notSet(string[] missing) returns Outcome => notSent(commons:SERVICE_UNAVAILABLE,
        "E-mail sending is not set up on this environment. Missing: " + string:'join(", ", ...missing));

// ---------------------------------------------------------------------------------------------
// Settings that must have a value, per way of sending
// ---------------------------------------------------------------------------------------------

isolated function exchangeMissing() returns string[] => core:missingOf({
    "smtpZepto.host": smtpZepto.host,
    "smtpZepto.user": smtpZepto.user,
    "smtpZepto.password": smtpZepto.password,
    "smtpZepto.fromAddress": smtpZepto.fromAddress
});

isolated function shoreMissing() returns string[] => core:missingOf({
    "tokenHTTPRequestConfig.url": tokenHTTPRequestConfig.url,
    "sendEmailHTTPRequestConfig.url": sendEmailHTTPRequestConfig.url,
    "mailClient.id": mailClient.id,
    "mailClient.secret": mailClient.secret,
    "mailClient.scope": mailClient.scope
});

isolated function shipMissing() returns string[] {
    string[] missing = core:missingOf({"smtp.host": smtp.host, "smtp.fromAddress": smtp.fromAddress});
    if smtp.to.length() == 0 {
        missing.push("smtp.to");
    }
    return missing;
}

// ---------------------------------------------------------------------------------------------
// Mail servers (Mule: Email_SMTP_Zepto and Email_SMTP)
// ---------------------------------------------------------------------------------------------

final email:SmtpClient? zeptoServer = check mailServerOf(smtpZepto, exchangeMissing().length() == 0);
final email:SmtpClient? shipServer = check mailServerOf(smtp, smtp.host.trim() != "");

isolated function mailServerOf(SmtpSettings settings, boolean usable) returns email:SmtpClient|error? {
    if !usable {
        return ();
    }
    email:Security security = check securityOf(settings.security);
    email:SmtpConfiguration options = {port: settings.port, security};
    if settings.caCertPath != "" {
        options.secureSocket = {cert: settings.caCertPath, protocol: {name: email:TLS, versions: ["TLSv1.2", "TLSv1.3"]}};
    }
    return check new (settings.host, settings.user == "" ? () : settings.user,
        settings.password == "" ? () : settings.password, options);
}

isolated function securityOf(string name) returns email:Security|error {
    match name {
        "SSL" => {
            return email:SSL;
        }
        "START_TLS_AUTO" => {
            return email:START_TLS_AUTO;
        }
        "START_TLS_ALWAYS" => {
            return email:START_TLS_ALWAYS;
        }
        "START_TLS_NEVER" => {
            return email:START_TLS_NEVER;
        }
    }
    return error("security must be SSL, START_TLS_AUTO, START_TLS_ALWAYS or START_TLS_NEVER");
}

# Mule: Send_EmailSub_Flow_Exchange.
#
# + payload - `{to, subject, body}`
# + correlationId - The request's correlation id
# + return - What became of the message
isolated function sendExchange(json payload, string correlationId) returns Outcome {
    core:Mail|string mail = core:exchangeMailOf(payload);
    if mail is string {
        return notSent(commons:BAD_REQUEST, mail);
    }
    email:SmtpClient? server = zeptoServer;
    if server is () {
        return notSet(exchangeMissing());
    }
    return handOver(server, smtpZepto, mail);
}

# Mule: Send_EmailSub_Flow_Ship.
#
# + payload - `{message: {subject, body: {content}, attachments?}}`
# + correlationId - The request's correlation id
# + return - What became of the message
isolated function sendShip(json payload, string correlationId) returns Outcome {
    core:Mail|string mail = core:shipMailOf(payload, smtp.to, smtp.cc);
    if mail is string {
        return notSent(commons:BAD_REQUEST, mail);
    }
    email:SmtpClient? server = shipServer;
    string[] missing = shipMissing();
    if server is () || missing.length() > 0 {
        return notSet(missing);
    }
    return handOver(server, smtp, mail);
}

const string TAKEN = "";
const string TOO_SLOW = "TOO_SLOW";

// The mail library has no time limit of its own, so the wait for the server is limited here.
isolated function handOver(email:SmtpClient server, SmtpSettings settings, core:Mail mail) returns Outcome {
    int recipients = mail.to.length() + mail.cc.length();
    future<string> sending = start deliver(server, settings.fromAddress, mail.cloneReadOnly());
    future<string> clock = start after(settings.timeoutSeconds);
    string|error result = wait sending | clock;
    if result is error {
        return notSent(commons:BAD_GATEWAY, "The mail server did not accept the message", result.message());
    }
    if result == TAKEN {
        return {sent: true, recipients};
    }
    if result == TOO_SLOW {
        return notSent(commons:TIMEOUT, "The mail server did not answer in time");
    }
    return notSent(commons:BAD_GATEWAY, "The mail server did not accept the message", result);
}

isolated function after(decimal seconds) returns string {
    runtime:sleep(seconds);
    return TOO_SLOW;
}

isolated function deliver(email:SmtpClient server, string fromAddress, core:Mail & readonly mail) returns string {
    email:Message message = {to: mail.to, subject: mail.subject, 'from: fromAddress, body: mail.body,
        contentType: "text/html"};
    if mail.cc.length() > 0 {
        message.cc = mail.cc;
    }
    core:Attachment? attachment = mail.attachment;
    if attachment is core:Attachment {
        mime:Entity|error part = fileOf(attachment);
        if part is error {
            return "The attachment could not be read: " + part.message();
        }
        message.attachments = part;
    }
    email:Error? refused = server->sendMessage(message);
    return refused is () ? TAKEN : (refused.message() == "" ? "refused" : refused.message());
}

isolated function fileOf(core:Attachment attachment) returns mime:Entity|error {
    mime:Entity part = new;
    part.setByteArray(check array:fromBase64(attachment.contentBase64), attachment.contentType);
    mime:ContentDisposition disposition = new;
    disposition.disposition = "attachment";
    disposition.fileName = attachment.name;
    part.setContentDisposition(disposition);
    return part;
}

// ---------------------------------------------------------------------------------------------
// The provider's HTTPS API (Mule: Send_EmailSub_Flow_Shore and AccessToken_SchedulerFlow)
// ---------------------------------------------------------------------------------------------

final http:Client? tokenEndpoint = check endpointOf(tokenHTTPRequestConfig);
final http:Client? sendMailEndpoint = check endpointOf(sendEmailHTTPRequestConfig);

isolated function endpointOf(commons:DownstreamSettings settings) returns http:Client|http:ClientError? {
    if core:missingOf({"url": settings.url}).length() > 0 {
        return ();
    }
    return check commons:newDownstreamClient(settings);
}

type KeptToken readonly & record {|
    string token;
    decimal since;
|};

isolated KeptToken keptToken = {token: "", since: 0};

# Mule: Send_EmailSub_Flow_Shore. The caller's body goes to the provider unchanged, with the
# application token. Repeated like the old API on a failed connection, a time-out or a 502.
#
# + payload - The caller's body, in the provider's own format
# + correlationId - The request's correlation id
# + return - What became of the message
isolated function sendShore(json payload, string correlationId) returns Outcome {
    http:Client? tokens = tokenEndpoint;
    http:Client? mails = sendMailEndpoint;
    string[] missing = shoreMissing();
    if tokens is () || mails is () || missing.length() > 0 {
        return notSet(missing);
    }
    int recipients = 0;
    json message = payload is map<json> ? payload["message"] : ();
    foreach string kind in ["toRecipients", "ccRecipients", "bccRecipients"] {
        json listed = message is map<json> ? message[kind] : ();
        recipients += listed is json[] ? listed.length() : 0;
    }
    int attempts = int:max(httpRetryCount, 0) + 1;
    boolean newToken = false;
    boolean tokenRenewed = false;
    Outcome last = notSent(commons:BAD_GATEWAY, "The mail provider could not be reached");
    foreach int attempt in 1 ... attempts {
        string|Outcome token = accessToken(tokens, newToken, correlationId);
        if token is Outcome {
            return token;
        }
        http:Response|http:ClientError reply = mails->post("", payload, {"Authorization": "Bearer " + token});
        if reply is http:Response && core:accepted(reply.statusCode) {
            return {sent: true, recipients, attempts: attempt};
        }
        boolean again;
        if reply is http:ClientError {
            string errorType = commons:errorTypeOfClientError(reply);
            last = notSent(errorType, "The mail provider could not be reached", attempts = attempt);
            again = true;
        } else {
            int status = reply.statusCode;
            string|http:ClientError text = reply.getTextPayload();
            string detail = text is string ? text : "";
            if status >= 300 && status < 400 {
                last = notSent(commons:BAD_GATEWAY, "The mail provider answered with a redirect (status "
                        + status.toString() + ") and took no message. Its address in the settings must be the "
                        + "https address", attempts = attempt);
                again = false;
            } else {
                last = notSent(commons:errorTypeOfStatus(status), "The mail provider did not accept the message",
                        detail, status, attempt);
                again = status == 502 || status == 504 || (status == 401 && !tokenRenewed);
                if status == 401 && !tokenRenewed {
                    tokenRenewed = true;
                    newToken = true;
                    continue;
                }
            }
        }
        newToken = false;
        if !again {
            return last;
        }
        if attempt < attempts {
            log:printWarn("Mail provider call is repeated", correlationId = correlationId, attempt = attempt,
                    attempts = attempts, errorType = last.errorType);
            runtime:sleep(httpRetryFrequencySeconds);
        }
    }
    return last;
}

// source-entry: AccessToken_SchedulerFlow
// The old API asked for a token every 55 minutes with a timer. Here the token is asked for when a
// message needs one and then kept for tokenMinutes, so nothing runs by itself.
isolated function accessToken(http:Client tokens, boolean renew, string correlationId) returns string|Outcome {
    if renew {
        error? dropped = state.remove(MAIL_TOKEN_KEY);
        if dropped is error {
            log:printWarn("Refused access token not removed from the state store", correlationId = correlationId);
        }
    }
    if !renew {
        KeptToken kept;
        lock {
            kept = keptToken;
        }
        if kept.token != "" && time:monotonicNow() - kept.since < <decimal>(mailClient.tokenMinutes * 60) {
            return kept.token;
        }
        // another copy of the service may have one already (old: object store, shared)
        string?|error shared = state.get(MAIL_TOKEN_KEY);
        if shared is string && shared != "" {
            lock {
                keptToken = {token: shared, since: time:monotonicNow()};
            }
            return shared;
        }
    }
    string|error form = tokenFormOf();
    if form is error {
        return notSent(commons:INTERNAL_SERVER_ERROR, "The token request could not be built");
    }
    decimal began = time:monotonicNow();
    http:Response|http:ClientError reply = tokens->post("", form, mediaType = "application/x-www-form-urlencoded");
    if reply is http:ClientError {
        // Once more: a connection that the provider closed while it was idle fails on first use.
        reply = tokens->post("", form, mediaType = "application/x-www-form-urlencoded");
    }
    if reply is http:ClientError {
        return notSent(commons:errorTypeOfClientError(reply), "The mail provider's token address could not be reached");
    }
    json|http:ClientError body = reply.getJsonPayload();
    json token = body is map<json> ? body["access_token"] : ();
    if !core:accepted(reply.statusCode) || token !is string || token == "" {
        // The provider's answer names the reason (for example a wrong client secret). Only its
        // short error code is kept; the description can carry ids.
        json code = body is map<json> ? body["error"] : ();
        return notSent(commons:BAD_GATEWAY, "The mail provider did not issue an access token (status "
                + reply.statusCode.toString() + "). Check mailClient.id and mailClient.secret",
                code is string ? code : "", reply.statusCode);
    }
    lock {
        keptToken = {token, since: time:monotonicNow()};
    }
    error? saved = state.put(MAIL_TOKEN_KEY, token, mailClient.tokenMinutes * 60);
    if saved is error {
        log:printWarn("Access token not kept in the state store", correlationId = correlationId, 'error = saved);
    }
    log:printInfo("Access token renewed", correlationId = correlationId, durationMs = millisSince(began));
    return token;
}

isolated function tokenFormOf() returns string|error {
    string form = "client_id=" + check url:encode(mailClient.id, "UTF-8");
    form += "&scope=" + check url:encode(mailClient.scope, "UTF-8");
    form += "&client_secret=" + check url:encode(mailClient.secret, "UTF-8");
    return form + "&grant_type=client_credentials";
}

// object store key of the old application
const string MAIL_TOKEN_KEY = "access_token";
