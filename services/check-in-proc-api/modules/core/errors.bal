// Answers and error handling of check-in-proc-api (Mule: check-in-proc-api-interface.xml and
// global-error-handler.xml).

# Mule's HTTP requester treats 200-299 as success and everything else as an error.
#
# + status - Status the backend answered with
# + return - True for a success
public isolated function isSuccess(int status) returns boolean => status >= 200 && status <= 299;

# Status of a successful answer: the backend's own for the operations that set `httpStatus`
# in Mule, 200 for the others (the listener's `vars.httpStatus default 200`).
#
# + backendStatus - True when the operation passes the backend's status on
# + status - Status the backend answered with
# + return - Status for the caller
public isolated function answerStatusOf(boolean backendStatus, int status) returns int =>
    backendStatus ? status : 200;

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

type Route [string, string[]];

final readonly & Route[] ROUTES = [
    ["GET", ["travelDocuments"]],
    ["POST", ["uploadDocuments"]],
    ["GET", ["travel-documents", "*"]],
    ["POST", ["travel-documents", "*", "file"]],
    ["POST", ["paymentToken"]],
    ["PUT", ["updateEmergencyContact"]],
    ["GET", ["getLinkedPerson"]]
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
            return [405, {"message": "Method not allowed"}];
        }
    }
    return [404, {"message": "Resource not found"}];
}

# A body as it is written to an error record: the JSON itself, the text when it is not JSON,
# and only the type and size for anything else (an upload is never copied into a record).
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

# What an error record says about an upload.
#
# + contentType - Content type of the upload
# + parts - Number of parts
# + return - Value for the record
public isolated function uploadRecordOf(string contentType, int parts) returns json =>
    {"contentType": baseMediaTypeOf(contentType), "parts": parts};

# Mule sub-flow `kafka`: the record is skipped when the error body or the saved request is empty.
#
# + requestRecord - The caller's request as it would be recorded
# + errorBody - The error answered to the caller
# + return - True when a record is written
public isolated function isPublishable(json requestRecord, json errorBody) returns boolean =>
    !isEmptyValue(requestRecord) && !isEmptyValue(errorBody);
