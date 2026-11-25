import ballerina/http;
import ballerina/uuid;

# Name of the header that carries the correlation id between layers (same as Mule).
public const string CORRELATION_HEADER = "correlationId";

# Returns the caller's correlation id, or a new one when the caller sent none.
# Mule: `attributes.headers.correlationId default uuid()`.
#
# + request - The inbound request
# + return - The correlation id to use for this request and every downstream call it makes
public isolated function correlationIdOf(http:Request request) returns string {
    string|http:HeaderNotFoundError header = request.getHeader(CORRELATION_HEADER);
    if header is string && header.trim() != "" {
        return header.trim();
    }
    return uuid:createType4AsString();
}

# Reads one header, or `()` when it is missing or blank.
#
# + request - The inbound request
# + name - Header name (case-insensitive)
# + return - The trimmed value, or `()`
public isolated function headerOf(http:Request request, string name) returns string? {
    string|http:HeaderNotFoundError value = request.getHeader(name);
    if value is string && value.trim() != "" {
        return value.trim();
    }
    return ();
}
