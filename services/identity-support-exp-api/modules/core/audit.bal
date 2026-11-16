import ballerina/crypto;

// Audit and error records (Mule: sub-flows `savepayload` and `kafka` in global-error-handler.xml)
// and the error e-mail (Mule: internal-sys-exp-api-exceptionSub_Flow). Field by field as in Mule,
// with one change on purpose: Mule put the caller's bearer token into session_id and auth_token
// in clear; here it is a SHA-256 fingerprint, so records still correlate per session but a
// reader of the topic cannot reuse the token.

const string SOURCE_API = "identity-support-exp-api";
final readonly & string[] REPLAYABLE = ["createReservation", "storeReservation", "addShorex", "addAddon",
    "CREATE_RESV", "STORE_RESV", "ADD_SHOREX", "ADD_ADDON"];

# What one call was, for its audit or error record.
#
# + correlationId - Correlation id
# + operationName - Mule `vars.operationName`: header x-operation-name, else the last path segment
# + operationType - Header x-operation-type
# + clientIp - Header x-forwarded-for
# + authorization - Authorization (or client_authorization) header as sent; only its fingerprint is kept
# + endpoint - Path of the call below the base path (Mule `attributes.maskedRequestPath`)
# + requestPayload - Request body as sent
public type CallFacts record {|
    string correlationId;
    string operationName;
    string operationType;
    string clientIp;
    string authorization;
    string endpoint;
    json requestPayload;
|};

# Producer connections of the Mule application (global-config.xml), one per target.
public const string PRODUCER_UAT = "Apache_Kafka_Producer_configuration_uat";
public const string PRODUCER_PROD_SHIP = "Apache_Kafka_Producer_configuration_prod_ship";
public const string PRODUCER_PROD_SHORE = "Apache_Kafka_Producer_configuration_prod_shore";

# Which producer connection a record goes through, as the Mule choice in `kafka` and `savepayload`:
# when p('mule.env') == 'prod' then (p('mule.deploymentTarget') == 'ship' ? prod_ship : prod_shore),
# otherwise uat.
#
# + muleEnv - Mule mule.env
# + deploymentTarget - Mule mule.deploymentTarget
# + return - The Mule producer connection name
public isolated function producerTargetOf(string muleEnv, string deploymentTarget) returns string {
    if muleEnv == "prod" {
        return deploymentTarget == "ship" ? PRODUCER_PROD_SHIP : PRODUCER_PROD_SHORE;
    }
    return PRODUCER_UAT;
}

# Mule `isEmpty(payload)` of the "Check Payload Before Kafka" choice: an empty payload is not published.
#
# + payload - The payload the record would be made of
# + return - True when Mule would skip the publish
public isolated function isEmptyPayload(json payload) returns boolean {
    if payload is () {
        return true;
    }
    if payload is string {
        return payload == "";
    }
    if payload is map<json> {
        return payload.length() == 0;
    }
    if payload is json[] {
        return payload.length() == 0;
    }
    return false;
}

# Mule `vars.operationName`.
#
# + header - x-operation-name header
# + endpoint - Path of the call
# + return - The operation name
public isolated function operationNameOf(string? header, string endpoint) returns string {
    if header is string && header != "" {
        return header;
    }
    string[] parts = re `/`.split(endpoint);
    return parts.length() > 0 ? parts[parts.length() - 1] : "";
}

# Session id of a record: the fingerprint of the bearer token (Mule: the token itself).
#
# + authorization - Header value as sent
# + loginToken - For operation Login, the token of the answer (Mule `data.login.token`)
# + isLogin - True for the Login operation
# + return - `sha256:<16 hex>` or "UNKNOWN"
public isolated function sessionIdOf(string authorization, json loginToken, boolean isLogin) returns string {
    string token = authorization.startsWith("Bearer ") ? authorization.substring(7) : authorization;
    if isLogin {
        token = loginToken is string ? loginToken : "";
    }
    if token.trim() == "" {
        return "UNKNOWN";
    }
    return "sha256:" + crypto:hashSha256(token.toBytes()).toBase16().substring(0, 16);
}

isolated function targetOf(string endpoint) returns string {
    string[] parts = re `/`.split(endpoint);
    return parts.length() > 1 && parts[1] != "" ? parts[1] : "UNKNOWN";
}

isolated function headersOf(CallFacts c) returns json => {
    "correlationId": c.correlationId == "" ? "UNKNOWN" : c.correlationId,
    "operationType": c.operationType == "" ? "UNKNOWN" : c.operationType,
    "operationName": c.operationName == "" ? "UNKNOWN" : c.operationName,
    "clientIp": c.clientIp == "" ? "UNKNOWN" : c.clientIp,
    "authorization": "MASKED"
};

# The audit record of a successful call (Mule `savepayload`, topic kafka.auditTopic).
#
# + c - The call
# + responsePayload - The answer sent back
# + createdAt - Time, ISO 8601
# + return - The record
public isolated function auditRecordOf(CallFacts c, json responsePayload, string createdAt) returns map<json> {
    boolean isLogin = c.operationName == "Login";
    string session = sessionIdOf(c.authorization, fieldAt(responsePayload, ["data", "login", "token"]), isLogin);
    string op = c.operationName == "" ? "UNKNOWN" : c.operationName;
    return {
        "session_id": session,
        "auth_token": session,
        "mule_correlation_id": c.correlationId == "" ? "UNKNOWN" : c.correlationId,
        "step_name": op,
        "source_api": SOURCE_API,
        "target_system": targetOf(c.endpoint),
        "request_method": "POST",
        "endpoint_url": c.endpoint == "" ? "UNKNOWN" : c.endpoint,
        "graphql_operation_name": op,
        "request_headers": headersOf(c),
        "request_payload": c.requestPayload ?: {},
        "response_status_code": 200,
        "response_headers": {},
        "response_payload": responsePayload ?: {},
        "status": "SUCCESS",
        "replayable": false,
        "retry_count": 0,
        "error_message": (),
        "created_at": createdAt
    };
}

# The error record of a failed call (Mule sub-flow `kafka`, topic kafka.errorTopic).
#
# + c - The call
# + statusCode - Status answered (Mule: the backend's status, else 500)
# + errorPayload - The error body
# + errorMessage - Error description
# + createdAt - Time, ISO 8601
# + return - The record
public isolated function errorRecordOf(CallFacts c, int statusCode, json errorPayload, string errorMessage,
        string createdAt) returns map<json> {
    boolean isLogin = c.operationName == "Login";
    string session = isLogin ? "UNKNOWN" : sessionIdOf(c.authorization, (), false);
    string op = c.operationName == "" ? "UNKNOWN" : c.operationName;
    return {
        "session_id": session,
        "auth_token": session,
        "mule_correlation_id": c.correlationId == "" ? "UNKNOWN" : c.correlationId,
        "step_name": op,
        "source_api": SOURCE_API,
        "target_system": targetOf(c.endpoint),
        "request_method": "POST",
        "endpoint_url": c.endpoint == "" ? "UNKNOWN" : c.endpoint,
        "graphql_operation_name": op,
        "request_headers": headersOf(c),
        "request_payload": c.requestPayload ?: {},
        "response_status_code": statusCode,
        "response_payload": errorPayload ?: {},
        "response_headers": {},
        "status": "FAILED",
        "replayable": REPLAYABLE.indexOf(op) != (),
        "retry_count": 0,
        "error_message": errorMessage == "" ? "UNKNOWN ERROR" : errorMessage,
        "created_at": createdAt
    };
}

# Importance of the error e-mail, as in this application's Mule flow.
#
# + errorType - Mule error type identifier
# + return - "High" or "Low"
public isolated function mailImportanceOf(string errorType) returns string =>
    ["BAD_GATEWAY", "INTERNAL_SERVER_ERROR", "SERVICE_UNAVAILABLE", "CONNECTIVITY"].indexOf(errorType) != ()
        ? "High" : "Low";

# The error e-mail body (Mule internal-sys-exp-api-exceptionSub_Flow), for the e-mail system API.
#
# + env - Mule `mule.env`
# + app - Mule `app`
# + errorType - Error type identifier
# + description - Error description
# + details - The error body, as text
# + toAddress - Mule `email.toAddress`
# + ccAddress - Mule `email.ccAddress`
# + attachment - Base64 of the failed request's payload (Mule `vars.emailAttachment`)
# + return - The body
public isolated function errorMailOf(string env, string app, string errorType, string description, string details,
        string toAddress, string ccAddress, string attachment) returns json => {
    "message": {
        "subject": env + " - " + app,
        "importance": mailImportanceOf(errorType),
        "body": {
            "contentType": "HTML",
            "content": "<b>Error type :</b> " + errorType + "<br/><b>Description :</b> " + description
                + "<br/><b>Details :</b> " + details
                + "<br/><br/><br/><span style='font-size: 12px;'><b>Important Note:</b><br/>For more information, "
                + "please refer to the MuleSoft application logs or contact the support team.</span>"
        },
        "toRecipients": [{"emailAddress": {"address": toAddress}}],
        "ccRecipients": [{"emailAddress": {"address": ccAddress}}],
        "attachments": [{
            "@odata.type": "#microsoft.graph.fileAttachment",
            "name": "batch_errors.txt",
            "contentType": "text/plain",
            "contentBytes": attachment
        }]
    }
};

# Mule error type of an answer status.
#
# + status - HTTP status
# + return - Error type identifier
public isolated function errorTypeOfStatus(int status) returns string {
    match status {
        400 => {return "BAD_REQUEST";}
        401 => {return "UNAUTHORIZED";}
        403 => {return "FORBIDDEN";}
        404 => {return "NOT_FOUND";}
        405 => {return "METHOD_NOT_ALLOWED";}
        408 => {return "TIMEOUT";}
        429 => {return "TOO_MANY_REQUESTS";}
        502 => {return "BAD_GATEWAY";}
        503 => {return "SERVICE_UNAVAILABLE";}
        504 => {return "TIMEOUT";}
    }
    return status >= 500 ? "INTERNAL_SERVER_ERROR" : "BAD_REQUEST";
}

isolated function fieldAt(json value, string[] path) returns json {
    json current = value;
    foreach string name in path {
        if current is map<json> {
            current = current[name];
        } else {
            return ();
        }
    }
    return current;
}
