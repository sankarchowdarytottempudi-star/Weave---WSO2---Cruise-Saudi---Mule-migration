import ballerina/lang.regexp;

// Pure functions of the e-mail service: what the old flows did to a request before sending it.

# The first attachment of a ship e-mail.
#
# + name - File name
# + contentType - Media type
# + contentBase64 - The content, base64
public type Attachment record {|
    string name;
    string contentType;
    string contentBase64;
|};

# One message, ready for a mail server.
#
# + to - Recipients
# + cc - Copy recipients
# + subject - Subject
# + body - HTML body
# + attachment - One attachment, if any
public type Mail record {|
    string[] to;
    string[] cc = [];
    string subject;
    string body;
    Attachment? attachment = ();
|};

# Mule: Send_EmailSub_Flow_Exchange, "Zepto SMTP body".
# `{to, subject, body}` becomes a message whose body is wrapped in a full HTML page.
#
# + payload - The caller's body
# + return - The message, or what is wrong with the request
public isolated function exchangeMailOf(json payload) returns Mail|string {
    if payload !is map<json> {
        return "The body must be an object with to, subject and body";
    }
    string[]|string recipients = recipientsOf(payload["to"]);
    if recipients is string {
        return recipients;
    }
    json subject = payload["subject"];
    if subject !is string || subject.trim() == "" {
        return "subject is required";
    }
    json body = payload["body"];
    if body is () || body is map<json> || body is json[] {
        return "body is required";
    }
    return {to: recipients, subject, body: htmlPageOf(body.toString())};
}

# Mule: Send_EmailSub_Flow_Ship, "Build SMTP email payload". The recipients are fixed settings;
# subject, body and the first attachment come from `message`.
#
# + payload - The caller's body
# + to - Fixed recipients
# + cc - Fixed copy recipients
# + return - The message, or what is wrong with the request
public isolated function shipMailOf(json payload, string[] to, string[] cc) returns Mail|string {
    json message = payload is map<json> ? payload["message"] : ();
    if message !is map<json> {
        return "message is required";
    }
    json subject = message["subject"];
    json bodyPart = message["body"];
    json content = bodyPart is map<json> ? bodyPart["content"] : ();
    if content is () || content is map<json> || content is json[] {
        return "message.body.content is required";
    }
    Attachment? attachment = ();
    json attachments = message["attachments"];
    if attachments is json[] && attachments.length() > 0 {
        json first = attachments[0];
        if first !is map<json> {
            return "message.attachments[0] must be an object";
        }
        json name = first["name"];
        json bytes = first["contentBytes"];
        json kind = first["contentType"];
        if name !is string || bytes !is string {
            return "message.attachments[0] needs name and contentBytes";
        }
        attachment = {name, contentBase64: bytes, contentType: kind is string ? kind : "application/octet-stream"};
    }
    return {to, cc, subject: subject is string ? subject : "", body: content.toString(), attachment};
}

# The recipients of `to`: one address or a list of them.
#
# + to - The `to` field
# + return - The addresses, or what is wrong
public isolated function recipientsOf(json to) returns string[]|string {
    json[] listed = [];
    if to is json[] {
        listed = to;
    } else if to !is () {
        listed = [to];
    }
    string[] out = [];
    foreach json one in listed {
        if one !is string || !looksLikeAddress(one) {
            return "to must hold e-mail addresses";
        }
        out.push(one.trim());
    }
    return out.length() == 0 ? "to is required" : out;
}

# A light check that keeps an obviously wrong value from reaching the mail server.
#
# + value - The candidate
# + return - True when it has one `@` with text on both sides and no line break
public isolated function looksLikeAddress(string value) returns boolean {
    string text = value.trim();
    int? at = text.indexOf("@");
    return at is int && at > 0 && at < text.length() - 1 && !text.includes("\n") && !text.includes("\r");
}

# Mule: `"<!DOCTYPE html><html><body>" ++ payload.body ++ "</body></html>"`.
#
# + body - The caller's HTML fragment
# + return - A full HTML page
public isolated function htmlPageOf(string body) returns string => "<!DOCTYPE html><html><body>" + body + "</body></html>";

# Only an answer in the 200 range means the provider took the message.
# A redirect (3xx) does not: nothing was sent.
#
# + status - HTTP status
# + return - True for 200 to 299
public isolated function accepted(int status) returns boolean => status >= 200 && status < 300;

# The names of the settings that have no value.
#
# + settings - Setting name and its value
# + return - The names whose value is empty or still the placeholder
public isolated function missingOf(map<string> settings) returns string[] {
    string[] names = [];
    foreach [string, string] [name, value] in settings.entries() {
        if value.trim() == "" || value == "http://localhost" {
            names.push(name);
        }
    }
    return names;
}

# Text that may be logged or answered: e-mail addresses are replaced, and it is kept short.
#
# + text - A mail server's or provider's message
# + return - The same text without addresses
public isolated function withoutAddresses(string text) returns string {
    string masked = re `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+`.replaceAll(text, "<address>");
    return masked.length() > 300 ? masked.substring(0, 300) : masked;
}

# True when the address is plain http to something that is not this machine or this cluster.
# Such an address answers with a redirect and sends nothing.
#
# + url - The address
# + return - True when it should be https
public isolated function shouldBeHttps(string url) returns boolean {
    if !url.startsWith("http://") {
        return false;
    }
    string rest = url.substring(7);
    string host = regexp:split(re `[:/]`, rest)[0];
    return !(host == "localhost" || host == "127.0.0.1" || host.endsWith(".svc") || host.endsWith(".local")
        || !host.includes("."));
}
