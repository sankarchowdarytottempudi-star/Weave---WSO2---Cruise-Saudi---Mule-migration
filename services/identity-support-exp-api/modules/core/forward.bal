// What is passed on to the Guest Identity process API, and the error answers of this API
// (Mule: generate-otp-impl.xml, verify-otp-impl.xml, guest_identity_impl.xml,
// guestProfile-Implimentation.xml, global-error-handler.xml).

# Headers of POST /otp/generate. Mule: `device_id` from client_deviceid (or client_device_id),
# `client-ip`, and the channel (source-system, else client_channel) under both of its names.
#
# + deviceId - The caller's device id, already trimmed, `()` when not sent
# + clientIp - The caller's `client-ip` header
# + sourceSystem - The caller's `source-system` header
# + clientChannel - The caller's `client_channel` header
# + return - Headers for the process API
public isolated function otpGenerateHeaders(string? deviceId, string? clientIp, string? sourceSystem,
        string? clientChannel) returns map<string> {
    map<string> headers = {};
    if deviceId is string {
        headers["device_id"] = deviceId;
    }
    if clientIp is string {
        headers["client-ip"] = clientIp;
    }
    string? channel = sourceSystem ?: clientChannel;
    if channel is string {
        headers["source-system"] = channel;
        headers["client_channel"] = channel;
    }
    return headers;
}

# The headers that are passed on under their own names, leaving out the ones the caller did not send.
#
# + values - Header name and the caller's value
# + return - Headers for the process API
public isolated function presentHeaders(map<string?> values) returns map<string> {
    map<string> headers = {};
    foreach [string, string?] [name, value] in values.entries() {
        if value is string {
            headers[name] = value;
        }
    }
    return headers;
}

# Query parameters that are passed on, leaving out the ones the caller did not send.
#
# + values - Parameter name and the caller's value
# + return - Query parameters for the process API
public isolated function presentQuery(map<string?> values) returns map<string[]> {
    map<string[]> query = {};
    foreach [string, string?] [name, value] in values.entries() {
        if value is string {
            query[name] = [value];
        }
    }
    return query;
}

# The error-mapping look-up (Mule sub-flow fetch-errors-db).
#
# + endpoint - Path of the operation that failed, for example /otp/verify
# + status - Status the process API answered with
# + return - Request body for the database system API
public isolated function errorMappingRequestOf(string endpoint, int status) returns map<json> => {
    "connectionKey": "PG_Guest",
    "operation": "Select",
    "query": "SELECT error ,type, code FROM cs_mule_framework.cs_error_mapping WHERE endpoint = :endpoint AND code = :code",
    "params": {"endpoint": endpoint == "" ? "UNKNOWN" : endpoint, "code": status.toString()}
};

# The error answer after the look-up: the first mapped row, or the backend's own answer when
# nothing is mapped.
#
# + rows - Answer of the database system API
# + original - The backend's error body
# + return - The body to answer with
public isolated function mappedErrorOf(json rows, json original) returns json {
    if rows is json[] && rows.length() > 0 {
        return rows[0];
    }
    return original;
}

# The body to answer with after the error-mapping look-up, or `()` when the process API's own
# answer has to be passed on: nothing is mapped for this error, or the mapping could not be read.
#
# + rows - Answer of the database system API, or why it could not be read
# + return - The mapped error body, `()` for the process API's own answer
public isolated function mappedBodyOf(json|error rows) returns json? {
    if rows is json[] && rows.length() > 0 {
        return rows[0];
    }
    return ();
}

# Mule's "Default Fallback Error Response". No longer answered when the error mapping cannot be
# read (the process API's own error is); kept for the record of the old shape.
#
# + sourceName - This API
# + target - The API that was called
# + return - Error body, answered with status 500
public isolated function fallbackErrorOf(string sourceName, string target) returns map<json> => {
    "messageType": "UNKNOWN",
    "message": "An unexpected error occurred",
    "responseCode": 500,
    "source": sourceName,
    "target": target,
    "errorDoesNotExist": true
};

# The answer when the backend gave no error body, or did not answer at all.
#
# + errorType - Error type, for example CONNECTIVITY
# + message - What happened
# + status - The backend's status, `()` when it did not answer
# + return - Error body
public isolated function plainErrorOf(string errorType, string message, int? status) returns map<json> => {
    "messageType": errorType,
    "message": message,
    "responseCode": status,
    "responsePayload": (),
    "errorDoesNotExist": false
};
