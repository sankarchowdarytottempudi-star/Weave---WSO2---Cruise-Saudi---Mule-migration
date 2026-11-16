// Answers, checks and error handling of person-profile-api (Mule: person-profile-proc-api-interface.xml,
// the APIkit router with the OAS spec person-profile-process-api 1.0.2, and global-error-handler.xml).

# Mule's HTTP requester treats 200-299 as success and everything else as an error.
#
# + status - Status the backend answered with
# + return - True for a success
public isolated function isSuccess(int status) returns boolean => status >= 200 && status <= 299;

# Status of an error answer (Mule: `vars.httpStatus default 500`, where `httpStatus` is the
# backend's status when it answered).
#
# + status - Status the backend answered with, `()` when it did not answer
# + return - Status for the caller
public isolated function errorStatusOf(int? status) returns int => status ?: 500;

# Mule `http-error-retrySub_Flow`: a failed call is repeated while repeats are left and the
# error is one of the configured types.
#
# + errorType - Error type of the failed call, for example CONNECTIVITY
# + retryTypes - Configured types, with or without the `HTTP:` prefix
# + retriesLeft - Repeats still allowed
# + return - True when the call is repeated
public isolated function shouldRetry(string errorType, string[] retryTypes, int retriesLeft) returns boolean {
    if retriesLeft <= 0 {
        return false;
    }
    foreach string name in retryTypes {
        string wanted = name.trim().toUpperAscii();
        if wanted.startsWith("HTTP:") {
            wanted = wanted.substring(5);
        }
        if wanted == errorType.toUpperAscii() {
            return true;
        }
    }
    return false;
}

# Mule "Set Custom Error variable": the answer when the backend gave no error body, or did not
# answer at all.
#
# + errorType - Error type, for example CONNECTIVITY
# + message - What happened
# + status - The backend's status, `()` when it did not answer
# + return - Error body
public isolated function customErrorOf(string errorType, string message, int? status) returns map<json> => {
    "messageType": errorType,
    "message": message,
    "responseCode": status,
    "responsePayload": (),
    "errorDoesNotExist": false
};

// APIkit router answers (Mule main flow error handler).
public const string BAD_REQUEST = "Bad request";
public const string NOT_FOUND = "Resource not found";
public const string METHOD_NOT_ALLOWED = "Method not allowed";
public const string UNSUPPORTED_MEDIA_TYPE = "Unsupported media type";

type Route [string, string[]];

final readonly & Route[] ROUTES = [
    ["GET", ["getEventsFolio"]],
    ["GET", ["getamenity"]],
    ["GET", ["getamenity-codes"]],
    ["GET", ["pos", "v1", "packages"]],
    ["GET", ["reservation", "v1", "person-search"]],
    ["GET", ["reservation", "v1", "person-search", "*"]],
    ["GET", ["reservation", "v1", "reservation-search", "*"]],
    ["POST", ["integration", "v1", "messages", "statuses"]],
    ["POST", ["integration", "v1", "messages"]],
    ["POST", ["reservation", "v1", "person-reservations", "actions", "bulk-update"]]
];

isolated function matches(string[] pattern, string[] path) returns boolean {
    if pattern.length() != path.length() {
        return false;
    }
    foreach int i in 0 ..< pattern.length() {
        if pattern[i] != "*" && pattern[i] != path[i] {
            return false;
        }
    }
    return true;
}

# The router's answer for a request that is not one of the operations (Mule APIkit):
# 405 for a known path with another method, 404 for an unknown path.
#
# + path - Path segments below the base path
# + return - Status and body
public isolated function routerAnswerOf(string[] path) returns [int, map<json>] {
    foreach [string, string[]] [_, pattern] in ROUTES {
        if matches(pattern, path) {
            return [405, {"message": METHOD_NOT_ALLOWED}];
        }
    }
    return [404, {"message": NOT_FOUND}];
}

# APIkit check of an integer query parameter (spec: `page` and `size` of /getEventsFolio).
#
# + value - The caller's value, `()` when it sent none
# + return - True when it is absent or an integer
public isolated function isIntegerOrAbsent(string? value) returns boolean {
    if value is () {
        return true;
    }
    int|error parsed = int:fromString(value.trim());
    return parsed is int && value.trim() != "";
}

# APIkit check of a POST body: the operations take `application/json` only (415 otherwise),
# the message operations require a JSON array, bulk-update takes an optional JSON object.
#
# + contentType - The caller's Content-Type
# + content - The caller's body
# + wanted - "array" (required) or "object" (optional)
# + return - `()` when the body is accepted, else status and body of the refusal
public isolated function bodyRefusalOf(string contentType, byte[] content, string wanted) returns [int, map<json>]? {
    boolean empty = content.length() == 0;
    if empty && wanted == "object" {
        return ();
    }
    if baseMediaTypeOf(contentType) != "application/json" {
        return [415, {"message": UNSUPPORTED_MEDIA_TYPE}];
    }
    if empty {
        return [400, {"message": BAD_REQUEST}];
    }
    string|error text = string:fromBytes(content);
    json|error parsed = text is string ? text.fromJsonString() : text;
    if parsed is error {
        return [400, {"message": BAD_REQUEST}];
    }
    if wanted == "array" && parsed !is json[] {
        return [400, {"message": BAD_REQUEST}];
    }
    if wanted == "object" && parsed !is map<json> {
        return [400, {"message": BAD_REQUEST}];
    }
    return ();
}

# A body as it is written to an error record: the JSON itself, the text when it is not JSON,
# and only the type and size for anything else.
#
# + contentType - Content type of the body
# + content - The body
# + return - Value for the record, `()` for no body
public isolated function bodyRecordOf(string contentType, byte[] content) returns json {
    if content.length() == 0 {
        return ();
    }
    string base = baseMediaTypeOf(contentType);
    boolean textual = base == "" || base.includes("json") || base.startsWith("text/") || base.includes("xml");
    string|error text = textual ? string:fromBytes(content) : error("not text");
    if text is error {
        return {"contentType": base, "bytes": content.length()};
    }
    json|error parsed = text.fromJsonString();
    return parsed is error ? text : parsed;
}

# Mule sub-flow `kafka`: the record is skipped when the error body or the saved request is empty.
#
# + requestRecord - The caller's request as it would be recorded (`vars.OGPayload`)
# + errorBody - The error answered to the caller
# + return - True when a record is written
public isolated function isPublishable(json requestRecord, json errorBody) returns boolean =>
    !isEmptyValue(requestRecord) && !isEmptyValue(errorBody);
