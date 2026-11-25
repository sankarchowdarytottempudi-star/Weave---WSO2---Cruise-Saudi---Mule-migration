import ballerina/http;

// Which inbound headers go to the next layer. Ported from the "Build Request Headers"
// DataWeave of reservation-mgr-exp-api: blank values are dropped
// (`filterObject (value != null and value != "")`).

# Inbound headers passed through unchanged to the next layer.
public const string[] PASS_THROUGH_HEADERS = [
    "Authorization",
    "client_id",
    "client_secret",
    "client_channel",
    "origin",
    "accept-language",
    "uniquePkgType",
    "X-Seaware-Authorization"
];

# Builds the headers for a downstream call.
#
# + request - The inbound request
# + correlationId - The request's correlation id
# + extra - Headers the service adds (`client_version`, `x-operation-name`, ...); blank values are dropped
# + return - Headers to send
public isolated function forwardHeaders(http:Request request, string correlationId, map<string?> extra = {})
        returns map<string> {
    map<string> headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
        [CORRELATION_HEADER]: correlationId
    };
    foreach string name in PASS_THROUGH_HEADERS {
        string? value = headerOf(request, name);
        if value is string {
            headers[name] = value;
        }
    }
    foreach [string, string?] [name, value] in extra.entries() {
        if value is string && value.trim() != "" {
            headers[name] = value;
        }
    }
    return headers;
}

# Client IP as Mule computed it: the remote address without port and leading slash.
#
# + caller - The caller
# + return - The IP address
public isolated function clientIpOf(http:Caller caller) returns string => caller.remoteAddress.ip;
