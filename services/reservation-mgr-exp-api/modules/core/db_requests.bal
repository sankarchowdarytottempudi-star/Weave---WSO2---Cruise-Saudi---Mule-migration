// db-sys-api request bodies, ported from the Mule transforms in
// reservation-mgr-experience-api-interface.xml. db-sys-api takes
// {connectionKey, operation, query, params}.

# Async request status values (Mule).
public enum AsyncStatus {
    IN_PROGRESS = "In-Progress",
    PROCESSED = "Processed",
    FAILED = "Failed"
}

# Body that records a new async request as In-Progress (insert, or update on conflict).
#
# + connectionKey - db-sys-api connection key
# + table - Status table
# + asyncId - The request's id (its correlation id)
# + description - Service name
# + payload - The original request
# + return - db-sys-api body
public isolated function asyncInsertBody(string connectionKey, string 'table, string asyncId, string description,
        json payload) returns json => {
    connectionKey,
    operation: "insert",
    query: string `INSERT INTO ${'table} (async_id, status, uuid, description, payload) VALUES (:uuid, :status, :uuid, `
        + ":description, CAST(:pl AS jsonb)) ON CONFLICT (async_id) DO UPDATE SET status = EXCLUDED.status, "
        + "description = EXCLUDED.description, payload = EXCLUDED.payload",
    params: {uuid: asyncId, status: IN_PROGRESS, description, pl: payload.toJsonString()}
};

# Body that records the outcome of an async request.
#
# + connectionKey - db-sys-api connection key
# + table - Status table
# + asyncId - The request's id
# + status - `Processed` or `Failed`
# + description - Service name
# + payload - Result, or the error body
# + return - db-sys-api body
public isolated function asyncUpdateBody(string connectionKey, string 'table, string asyncId, AsyncStatus status,
        string description, json payload) returns json => {
    connectionKey,
    operation: "update",
    query: string `UPDATE ${'table} SET status = :status, description = :description, payload = CAST(:payload AS jsonb) `
        + "WHERE async_id = :uuid",
    params: {status, description, uuid: asyncId, payload: payload.toJsonString()}
};

# Body that reads the status of an async request.
#
# + connectionKey - db-sys-api connection key
# + table - Status table
# + asyncId - The id the caller received
# + return - db-sys-api body
public isolated function asyncSelectBody(string connectionKey, string 'table, string asyncId) returns json => {
    connectionKey,
    operation: "select",
    query: string `SELECT async_id, status, uuid, description, payload FROM ${'table} WHERE async_id = :uuid`,
    params: {uuid: asyncId}
};

# Body that looks up a mapped error message in cs_mule_framework.cs_error_mapping (columns
# endpoint, error, type, code, as in Mule; see QA_RESILIENCE_ROUTING_VERIFICATION.md).
#
# + connectionKey - db-sys-api connection key
# + query - Configured select; parameters `:endpoint`, `:code`, `:type`
# + endpoint - Inbound request path, e.g. `/reservation-mgr-exp-api/v1/integration-tasks`
# + code - HTTP status about to be returned (the table stores it as text)
# + errorType - Error type about to be returned
# + return - db-sys-api body
public isolated function errorMappingBody(string connectionKey, string query, string endpoint, int code,
        string errorType) returns json => {
    connectionKey,
    operation: "select",
    query,
    params: {endpoint, code: code.toString(), 'type: errorType}
};

# The Mule mapped-error body, from the rows a lookup returned.
#
# The row whose `type` equals the error type wins; a row with a blank or null `type` is the
# generic fallback for that endpoint and code. No usable row gives `()`: the original error
# is returned unchanged. Accepts a bare array of rows or `{"data": [...]}`.
#
# + answer - db-sys-api answer
# + errorType - Error type about to be returned
# + code - HTTP status about to be returned
# + correlationId - The request's correlation id
# + return - `{messageType, message, responseCode, correlationId, errorDoesNotExist}`, or `()`
public isolated function mappedErrorBodyOf(json answer, string errorType, int code, string correlationId) returns json {
    json rows = answer;
    if answer is map<json> {
        rows = answer["data"];
    }
    if rows !is json[] {
        return ();
    }
    map<json>? exact = ();
    map<json>? fallback = ();
    foreach json row in rows {
        if row !is map<json> || row["error"] !is string {
            continue;
        }
        json t = row["type"];
        if t is string && t.trim() == errorType && exact is () {
            exact = row;
        } else if (t is () || (t is string && t.trim() == "")) && fallback is () {
            fallback = row;
        }
    }
    map<json>? chosen = exact ?: fallback;
    if chosen is () {
        return ();
    }
    return {
        messageType: errorType,
        message: chosen["error"],
        responseCode: code,
        correlationId,
        errorDoesNotExist: false
    };
}
