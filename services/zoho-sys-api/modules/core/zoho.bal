// Rules of zoho-sys-api that need no network: where a request goes in Zoho, how the access token
// is asked for and how Zoho's answers are read. Ported by hand from the Mule flows
// `zoho-sys-api-flow` and `Get_Zoho_token`.

import ballerina/lang.array;
import ballerina/url;

# The Zoho OAuth client the service signs in with.
#
# + clientId - Client id
# + clientSecret - Client secret
# + refreshToken - Long-lived refresh token the access tokens are issued from
public type ZohoAccount record {|
    string clientId = "";
    string clientSecret = "";
    string refreshToken = "";
|};

# True while a backend address is still the generator's placeholder.
#
# + address - Configured address
# + return - True when it is empty or points at localhost
public isolated function isPlaceholderAddress(string address) returns boolean {
    string u = address.trim().toLowerAscii();
    return u == "" || u.includes("//localhost") || u.includes("//127.0.0.1");
}

# Name of the first account setting that is still empty.
#
# + account - Configured account
# + return - Setting name, `()` when the account is complete
public isolated function missingAccountSetting(ZohoAccount account) returns string? {
    if account.clientId.trim() == "" {
        return "zohoAccount.clientId";
    }
    if account.clientSecret.trim() == "" {
        return "zohoAccount.clientSecret";
    }
    if account.refreshToken.trim() == "" {
        return "zohoAccount.refreshToken";
    }
    return ();
}

# The Zoho path a request is sent to.
#
# Mule `zohoApiPath`: the `zohoPath` header wins; otherwise the path is built from the part of the
# caller's address after `/zoho`: the module, and the record id when there is one. Anything deeper
# is not used (a longer Zoho path is given in the `zohoPath` header).
#
# + header - Value of the `zohoPath` header, if sent
# + segments - Parts of the caller's address after `/zoho`
# + prefix - Start of a Zoho CRM path
# + return - Zoho path, "" when the request names neither
public isolated function zohoPathOf(string? header, string[] segments, string prefix = "/crm/v2/") returns string {
    if header is string && header.trim() != "" {
        string path = header.trim();
        return path.startsWith("/") ? path : "/" + path;
    }
    if segments.length() == 0 || segments[0].trim() == "" {
        return "";
    }
    string path = (prefix.endsWith("/") ? prefix : prefix + "/") + encoded(segments[0].trim());
    if segments.length() > 1 && segments[1].trim() != "" {
        path += "/" + encoded(segments[1].trim());
    }
    return path;
}

# True when a path can be appended to the Zoho address as it is: it starts with one "/" and has
# no blanks, control characters or backslashes.
#
# + path - Zoho path
# + return - True when it is safe to send
public isolated function isSafePath(string path) returns boolean {
    if !path.startsWith("/") || path.startsWith("//") {
        return false;
    }
    foreach int codePoint in path.toCodePointInts() {
        if codePoint <= 32 || codePoint == 127 || codePoint == 92 {
            return false;
        }
    }
    return true;
}

# True when the path is a record's photo (Mule: last part of the path is `photo`).
#
# + path - Zoho path
# + return - True for a photo path
public isolated function isPhotoPath(string path) returns boolean {
    string p = path;
    int? query = p.indexOf("?");
    if query is int {
        p = p.substring(0, query);
    }
    return p == "photo" || p.endsWith("/photo");
}

# Body of the access-token request (form encoded), as Mule `Get_Zoho_token` sent it.
#
# + account - Zoho OAuth client
# + return - Form-encoded body
public isolated function tokenFormOf(ZohoAccount account) returns string =>
    "grant_type=refresh_token&client_id=" + encoded(account.clientId.trim())
    + "&client_secret=" + encoded(account.clientSecret.trim())
    + "&refresh_token=" + encoded(account.refreshToken.trim());

# The access token in Zoho's answer to a token request.
#
# + answer - Zoho's answer
# + return - Access token, or an error that carries Zoho's reason code and nothing else
public isolated function accessTokenOf(json answer) returns string|error {
    if answer is map<json> {
        json token = answer["access_token"];
        if token is string && token.trim() != "" {
            return token.trim();
        }
        json reason = answer["error"];
        if reason is string && isCode(reason) {
            return error("Zoho did not issue an access token (" + reason + ")");
        }
    }
    return error("Zoho did not issue an access token");
}

# Value of the Authorization header Zoho expects.
#
# + token - Access token
# + return - Header value
public isolated function authorizationOf(string token) returns string => "Zoho-oauthtoken " + token;

# True when a cached access token can be used for the next call.
#
# + token - Cached token ("" when there is none)
# + expiresAt - Second (epoch) until which it is reused
# + now - Current second (epoch)
# + rejected - A token Zoho has just refused ("" when none)
# + return - True when the cached token is still good
public isolated function tokenUsable(string token, int expiresAt, int now, string rejected = "") returns boolean =>
    token != "" && token != rejected && now < expiresAt;

# True when Zoho refused a call because the access token is no longer valid
# (Mule: `error.errorMessage.payload.message == "invalid oauth token"`).
#
# + body - Zoho's answer
# + return - True when a new token should be asked for
public isolated function isExpiredTokenAnswer(json body) returns boolean {
    if body is map<json> {
        json message = body["message"];
        if message is string && message.trim().toLowerAscii() == "invalid oauth token" {
            return true;
        }
        json code = body["code"];
        return code is string && code.trim() == "INVALID_TOKEN";
    }
    return false;
}

# Zoho's answer as JSON; text when it is not JSON; `()` when it is empty.
#
# + raw - Bytes of the answer
# + return - The answer
public isolated function answerOf(byte[] raw) returns json {
    if raw.length() == 0 {
        return ();
    }
    string|error text = string:fromBytes(raw);
    if text is error {
        return ();
    }
    json|error parsed = text.fromJsonString();
    return parsed is error ? text : parsed;
}

# Error type name for a status Zoho answered with (the names Mule's HTTP connector used).
#
# + status - HTTP status
# + return - Error type
public isolated function errorTypeOfStatus(int status) returns string {
    match status {
        400 => {
            return "BAD_REQUEST";
        }
        401 => {
            return "UNAUTHORIZED";
        }
        403 => {
            return "FORBIDDEN";
        }
        404 => {
            return "NOT_FOUND";
        }
        405 => {
            return "METHOD_NOT_ALLOWED";
        }
        406 => {
            return "NOT_ACCEPTABLE";
        }
        415 => {
            return "UNSUPPORTED_MEDIA_TYPE";
        }
        429 => {
            return "TOO_MANY_REQUESTS";
        }
        502 => {
            return "BAD_GATEWAY";
        }
        503 => {
            return "SERVICE_UNAVAILABLE";
        }
        504 => {
            return "GATEWAY_TIMEOUT";
        }
    }
    return status >= 500 ? "INTERNAL_SERVER_ERROR" : "CLIENT_ERROR";
}

# Message of the error answer (Mule: `error.errorMessage.payload.message default error.description`).
#
# + body - Zoho's answer
# + status - Status Zoho answered with
# + return - Message for the caller
public isolated function errorMessageOf(json body, int status) returns string {
    if body is map<json> {
        json message = body["message"];
        if message is string && message.trim() != "" {
            return message;
        }
    }
    return "Zoho answered " + status.toString();
}

# The photo of an upload request (Mule: `fromBase64(payload.file)`).
#
# + payload - Caller's JSON body
# + return - Bytes of the photo, or an error that says what is wrong with the body
public isolated function photoBytesOf(json payload) returns byte[]|error {
    if payload is map<json> {
        json file = payload["file"];
        if file is string && file.trim() != "" {
            byte[]|error bytes = array:fromBase64(file.trim());
            if bytes is byte[] && bytes.length() > 0 {
                return bytes;
            }
            return error("The photo in `file` is not valid base64");
        }
    }
    return error("The body must carry the photo as base64 text in `file`");
}

# A path with query parameters added (values are URL-encoded).
#
# + path - Path, which may already carry a query string
# + params - Parameters to add
# + return - The path with the parameters
public isolated function withQuery(string path, map<string[]> params) returns string {
    string out = path;
    foreach [string, string[]] [name, values] in params.entries() {
        foreach string value in values {
            out += (out.includes("?") ? "&" : "?") + encoded(name) + "=" + encoded(value);
        }
    }
    return out;
}

isolated function encoded(string value) returns string {
    string|url:Error result = url:encode(value, "UTF-8");
    return result is string ? result : value;
}

// A short reason code such as `invalid_client`: letters, digits and underscores only.
isolated function isCode(string value) returns boolean {
    if value.length() == 0 || value.length() > 40 {
        return false;
    }
    foreach int c in value.toCodePointInts() {
        boolean ok = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
        if !ok {
            return false;
        }
    }
    return true;
}
