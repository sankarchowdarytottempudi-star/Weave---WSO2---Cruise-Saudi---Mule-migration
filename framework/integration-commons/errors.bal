import ballerina/http;
import ballerina/time;

// The error contract shared by all layers, ported from Global_Error_Handler in both Mule
// projects. Callers (web, mobile, other APIs) already parse this shape, so its member names
// are kept exactly.

# The error body every API returns.
#
# + timestamp - When the error was produced (ISO-8601, UTC)
# + statusCode - HTTP status, repeated in the body as Mule did
# + message - Human-readable summary
# + correlationId - The request's correlation id
# + error - Error type identifier (`BAD_REQUEST`, `CIRCUIT_OPEN`, `TIMEOUT`, ...)
# + targetError - The downstream error body when there is one, otherwise a detail string
public type ErrorEnvelope record {|
    string timestamp;
    int statusCode;
    string message;
    string correlationId;
    string 'error;
    json targetError = ();
|};

# Error types the platform raises itself (Mule `CUSTOM:*` / APIkit types).
public enum ErrorType {
    BAD_REQUEST = "BAD_REQUEST",
    UNAUTHORIZED = "UNAUTHORIZED",
    INVALID_REQUEST = "INVALID_REQUEST",
    GRAPHQL_QUERY = "GRAPHQL_QUERY",
    NOT_IMPLEMENTED = "NOT_IMPLEMENTED",
    NOT_FOUND = "NOT_FOUND",
    CIRCUIT_OPEN = "CIRCUIT_OPEN",
    TIMEOUT = "TIMEOUT",
    CONNECTIVITY = "CONNECTIVITY",
    BAD_GATEWAY = "BAD_GATEWAY",
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE",
    INTERNAL_SERVER_ERROR = "INTERNAL_SERVER_ERROR"
}

// Mule: the `statusCode` choice in Global_Error_Handler (exp-api has the longest list).
final readonly & map<int> STATUS_BY_ERROR_TYPE = {
    "BAD_REQUEST": 400,
    "REQUEST": 400,
    "INVALID_REQUEST": 400,
    "INVALID_CONNECTION_KEY": 400,
    "SYNTAX_ERROR": 400,
    "GRAPHQL_QUERY": 400,
    "EXPRESSION": 400,
    "UNAUTHORIZED": 401,
    "EMPTY_RESPONSE": 404,
    "NOT_FOUND": 404,
    "VALIDATION_ERROR": 406,
    "NOT_IMPLEMENTED": 501,
    "CIRCUIT_OPEN": 503,
    "SERVICE_UNAVAILABLE": 503,
    "BAD_GATEWAY": 502,
    "CONNECTIVITY": 502,
    "TIMEOUT": 504
};

# HTTP status for an error type. A downstream status, when known, wins for types the table
# does not list, as `error.exception.errorMessage.attributes.statusCode default 500` did.
#
# + errorType - Error type identifier
# + downstreamStatus - Status the downstream answered with, if any
# + return - The HTTP status to answer with
public isolated function statusForErrorType(string errorType, int? downstreamStatus = ()) returns int {
    int? mapped = STATUS_BY_ERROR_TYPE[errorType];
    if mapped is int {
        return mapped;
    }
    return downstreamStatus ?: 500;
}

# Builds the error envelope.
#
# + errorType - Error type identifier
# + message - Summary for the caller
# + correlationId - The request's correlation id
# + downstreamStatus - Downstream HTTP status, if the error came from a downstream call
# + targetError - Downstream body or detail
# + return - The envelope
public isolated function envelopeOf(string errorType, string message, string correlationId,
        int? downstreamStatus = (), json targetError = ()) returns ErrorEnvelope => {
    timestamp: time:utcToString(time:utcNow()),
    statusCode: statusForErrorType(errorType, downstreamStatus),
    message,
    correlationId,
    'error: errorType,
    targetError
};

# Builds the HTTP response for an envelope, with the correlation id echoed in a header.
#
# + envelope - The error body
# + extraHeaders - More headers to set, for example `Retry-After`
# + return - The response
public isolated function errorResponse(ErrorEnvelope envelope, map<string> extraHeaders = {}) returns http:Response {
    http:Response response = new;
    response.statusCode = envelope.statusCode;
    response.setJsonPayload(envelope.toJson());
    response.setHeader(CORRELATION_HEADER, envelope.correlationId);
    foreach [string, string] [name, value] in extraHeaders.entries() {
        response.setHeader(name, value);
    }
    return response;
}

# Maps a Ballerina HTTP client error to the Mule error type it corresponds to, so retry
# rules, circuit-breaker rules and error mapping configured with Mule names keep working.
#
# + err - The client error
# + return - Mule-style error type identifier
public isolated function errorTypeOfClientError(http:ClientError err) returns string {
    if err is http:IdleTimeoutError {
        return TIMEOUT;
    }
    if err is http:ApplicationResponseError {
        int status = err.detail().statusCode;
        return errorTypeOfStatus(status);
    }
    return CONNECTIVITY;
}

# Mule HTTP error type for a downstream status code.
#
# + status - HTTP status
# + return - Error type identifier
public isolated function errorTypeOfStatus(int status) returns string {
    match status {
        400 => {
            return BAD_REQUEST;
        }
        401 => {
            return UNAUTHORIZED;
        }
        404 => {
            return NOT_FOUND;
        }
        500 => {
            return INTERNAL_SERVER_ERROR;
        }
        502 => {
            return BAD_GATEWAY;
        }
        503 => {
            return SERVICE_UNAVAILABLE;
        }
        504 => {
            return "GATEWAY_TIMEOUT";
        }
    }
    return status >= 500 ? INTERNAL_SERVER_ERROR : BAD_REQUEST;
}
