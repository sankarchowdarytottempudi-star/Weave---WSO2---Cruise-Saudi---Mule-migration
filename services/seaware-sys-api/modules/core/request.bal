// Pure request/response helpers for seaware-sys-api, testable without HTTP.

# The GraphQL text of a body of the form `{"query": "..."}`.
#
# + body - Raw request body
# + return - The query text, empty when the body is not such a document
public isolated function queryTextOf(byte[] body) returns string {
    json parsed = bodyAsJson(body);
    if parsed is map<json> {
        json query = parsed["query"];
        if query is string {
            return query;
        }
    }
    return "";
}

# The body as JSON, or `()` when it is not JSON (for audit records).
#
# + body - Raw body
# + return - Parsed JSON or `()`
public isolated function bodyAsJson(byte[] body) returns json {
    string|error text = string:fromBytes(body);
    if text is error {
        return ();
    }
    json|error parsed = text.fromJsonString();
    return parsed is error ? () : parsed;
}

# Headers sent to Seaware (Mule: Authorization, Content-Type, Accept, correlationId).
#
# + authorization - The caller's Authorization header, if any
# + correlationId - The request's correlation id
# + return - Headers
public isolated function seawareHeaders(string? authorization, string correlationId, string? seawareAuth = ()) returns map<string> {
    map<string> headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "correlationId": correlationId
    };
    // The agent/booking session token (caller sends it in X-Seaware-Authorization) is what Seaware
    // authorises write operations against; it takes precedence over the gateway OAuth token, which
    // now occupies Authorization and is meaningless to Seaware.
    if seawareAuth is string && seawareAuth.trim() != "" {
        string t = seawareAuth.trim();
        headers["Authorization"] = t.startsWith("Bearer ") ? t : "Bearer " + t;
    } else if authorization is string {
        headers["Authorization"] = authorization;
    }
    return headers;
}

# Error message for the envelope. Mule: `payload.message default error.description`.
#
# + downstream - Downstream error body
# + errorType - Error type, used when the body has no message
# + return - The message
public isolated function messageOf(json downstream, string errorType) returns string {
    if downstream is map<json> {
        json message = downstream["message"];
        if message is string {
            return message;
        }
    }
    return string `Seaware answered ${errorType}`;
}
