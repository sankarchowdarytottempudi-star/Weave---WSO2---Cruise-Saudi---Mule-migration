// Rules of otalio-sys-api-new that need no network: which Otalio path an operation goes to, what
// is passed on, how the sign-in answers are read. Ported by hand from the Mule flows in
// `otalio-sys-api-implementation.xml` and `accessToken.xml`.

import ballerina/url;

# The account the service signs in to Otalio with.
#
# + login - Login name
# + password - Password
public type OtalioAccount record {|
    string login = "";
    string password = "";
|};

# What the service remembers between calls about its Otalio sign-in.
#
# + refreshToken - Refresh token of the last sign-in ("" when there is none)
# + refreshExpiresAt - Second (epoch) until which the refresh token is reused
# + authorization - Authorization header value in use ("" when there is none)
# + authorizationExpiresAt - Second (epoch) until which it is reused
public type TokenState record {|
    string refreshToken = "";
    int refreshExpiresAt = 0;
    string authorization = "";
    int authorizationExpiresAt = 0;
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
public isolated function missingAccountSetting(OtalioAccount account) returns string? {
    if account.login.trim() == "" {
        return "otalioAccount.login";
    }
    if account.password == "" {
        return "otalioAccount.password";
    }
    return ();
}

# First value of a query parameter; `()` when it is absent or empty.
#
# + query - Query parameters
# + name - Parameter name
# + return - The value
public isolated function firstOf(map<string[]> query, string name) returns string? {
    string[]? values = query[name];
    if values is string[] && values.length() > 0 && values[0].trim() != "" {
        return values[0].trim();
    }
    return ();
}

# Query parameters without the ones the service uses itself
# (Mule: `attributes.queryParams filterObject k != "operationName"`).
#
# + query - Caller's query parameters
# + dropped - Names not passed on
# + return - Parameters passed on to Otalio
public isolated function without(map<string[]> query, string[] dropped) returns map<string[]> {
    map<string[]> kept = {};
    foreach [string, string[]] [name, values] in query.entries() {
        if dropped.indexOf(name) is () {
            kept[name] = values;
        }
    }
    return kept;
}

# The Otalio path of an operation, with `{ID}` replaced by the ship/record id.
#
# Mule: `p("OtalioConfigDetails." ++ operationName ++ ".path")`, then `{ID}` replaced by the
# query parameter `shipId` (default "").
#
# + operationPaths - Configured paths by operation name
# + operationName - Operation the caller named
# + id - Value of `shipId` ("" when not sent)
# + return - Otalio path, or an error for an operation that is not configured
public isolated function targetPathOf(map<string> operationPaths, string operationName, string id)
        returns string|error {
    string? configured = operationPaths[operationName];
    if configured is () || configured.trim() == "" {
        return error("Unknown operationName: " + printable(operationName));
    }
    string path = configured.trim();
    if !path.startsWith("/") {
        path = "/" + path;
    }
    while path.includes("{ID}") {
        int? at = path.indexOf("{ID}");
        if at is int {
            path = path.substring(0, at) + encoded(id) + path.substring(at + 4);
        }
    }
    return path;
}

# True when a caller-given path can be appended to the Otalio address as it is.
#
# + path - Path
# + return - True when it starts with one "/" and has no blanks, control characters or backslashes
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

# HTTP method of an operation called through GET /integration-tasks
# (Mule: `deleteCustomValue` is a DELETE, every other operation a GET).
#
# + operationName - Operation the caller named
# + return - DELETE or GET
public isolated function readMethodOf(string operationName) returns string =>
    operationName == "deleteCustomValue" ? "DELETE" : "GET";

# HTTP method of an operation called through POST /integration-tasks (query parameter
# `httpMethod`, default POST; Mule accepted POST, PATCH and PUT).
#
# + httpMethod - Value of `httpMethod`, if sent
# + return - POST, PATCH or PUT, or an error for any other method
public isolated function writeMethodOf(string? httpMethod) returns string|error {
    if httpMethod is () || httpMethod.trim() == "" {
        return "POST";
    }
    string method = httpMethod.trim().toUpperAscii();
    if method == "POST" || method == "PATCH" || method == "PUT" {
        return method;
    }
    return error("Unsupported HTTP Method: " + printable(httpMethod.trim()));
}

# True when a caller's header is passed on to Otalio. Mule passed every header except
# Authorization; headers that belong to one connection, the body headers (set again for the
# outgoing call) and the gateway's own identity token are left out here.
#
# + name - Header name
# + return - True when it is passed on
public isolated function isForwardedHeader(string name) returns boolean {
    string n = name.trim().toLowerAscii();
    return NOT_FORWARDED.indexOf(n) is () && !n.startsWith("proxy-");
}

final readonly & string[] NOT_FORWARDED = [
    "authorization", "host", "content-length", "content-type", "transfer-encoding", "connection", "keep-alive",
    "upgrade", "te", "trailer", "expect", "accept-encoding", "x-jwt-assertion"
];

# Body of the sign-in request (Mule: `{password, login}`).
#
# + account - Service account
# + return - JSON body
public isolated function loginBodyOf(OtalioAccount account) returns json =>
    {password: account.password, login: account.login.trim()};

# Body of the access-token request (Mule: `{refreshToken}`).
#
# + refreshToken - Refresh token of the sign-in
# + return - JSON body
public isolated function refreshBodyOf(string refreshToken) returns json => {refreshToken};

# Refresh token in a sign-in answer (Mule: `payload.responsePayload.refresh_token`).
#
# + answer - Otalio's answer
# + return - Refresh token, `()` when there is none
public isolated function refreshTokenOf(json answer) returns string? => tokenField(answer, "refresh_token");

# Access token in a sign-in or refresh answer (Mule: `payload.responsePayload.access_token`).
#
# + answer - Otalio's answer
# + return - Access token, `()` when there is none
public isolated function accessTokenOf(json answer) returns string? => tokenField(answer, "access_token");

# Value of the Authorization header Otalio expects (Mule: `"Bearer " ++ access_token`).
#
# + accessToken - Access token
# + return - Header value
public isolated function bearerOf(string accessToken) returns string => "Bearer " + accessToken;

# Seconds an access token is reused: what Otalio says it lives (less a margin of 30 seconds), never
# longer than the configured limit; the limit itself when Otalio does not say.
#
# + answer - Otalio's sign-in or refresh answer
# + maxSeconds - Configured longest reuse, in seconds (0 = never reuse)
# + return - Seconds to reuse the token
public isolated function accessLifetimeOf(json answer, int maxSeconds) returns int {
    if maxSeconds <= 0 {
        return 0;
    }
    if answer is map<json> {
        json inner = answer["responsePayload"];
        if inner is map<json> {
            json expiresIn = inner["expires_in"];
            if expiresIn is int|float|decimal {
                int seconds = <int>expiresIn - 30;
                return seconds <= 0 ? 0 : int:min(maxSeconds, seconds);
            }
        }
    }
    return maxSeconds;
}

# True when the remembered Authorization value can be used for the next call.
#
# + state - What the service remembers
# + now - Current second (epoch)
# + rejected - A value Otalio has just refused ("" when none)
# + return - True when it is still good
public isolated function authorizationUsable(TokenState state, int now, string rejected = "") returns boolean =>
    state.authorization != "" && state.authorization != rejected && now < state.authorizationExpiresAt;

# True when the remembered refresh token can be used to ask for an access token.
#
# + state - What the service remembers
# + now - Current second (epoch)
# + return - True when it is still good
public isolated function refreshUsable(TokenState state, int now) returns boolean =>
    state.refreshToken != "" && now < state.refreshExpiresAt;

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

isolated function tokenField(json answer, string name) returns string? {
    if answer is map<json> {
        json inner = answer["responsePayload"];
        if inner is map<json> {
            json value = inner[name];
            if value is string && value.trim() != "" {
                return value.trim();
            }
        }
    }
    return ();
}

isolated function encoded(string value) returns string {
    string|url:Error result = url:encode(value, "UTF-8");
    return result is string ? result : value;
}

// A caller's text made safe to repeat in an error message: letters, digits, "-", "_" and "."
// only, at most 60 characters.
isolated function printable(string value) returns string {
    string out = "";
    foreach int c in value.toCodePointInts() {
        boolean ok = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 45 || c == 95
            || c == 46;
        if ok && out.length() < 60 {
            string|error ch = string:fromCodePointInt(c);
            out += ch is string ? ch : "";
        }
    }
    return out;
}
