// db-sys-api (DB System API) - written by hand from the Mule application.
//
// Operation
//   ANY /db   runs one SQL statement on the PostgreSQL database and answers with its result
//
// The caller sends {"connectionKey", "operation", "query", "params"}:
//   connectionKey  "PG_ShipTracking" or "PG_Guest": the database account to use
//   operation      "select" (answers the rows), "insert" or "update" (answer the number of rows)
//   query          the SQL text, with :name where a value goes
//   params         the values by name; they are bound as parameters, never put into the text
//
// THIS API RUNS THE SQL ITS CALLER SENDS. It has no login of its own (the old one had none
// either). Whoever can reach it can read and change everything the two database accounts can.
// Keep it inside the cluster and do not publish it on a gateway.
//
// Not ported: Kafka audit and error publishing (switched off in the old settings; log lines
// instead) and the error e-mail settings (not used by the old flow).
//
// Deliberately different from Mule
//   - Without database settings the service starts and answers 503 naming the settings that
//     are missing. Mule did not start without them.
//   - Mistakes of the caller are 400 BAD_REQUEST: a body that is not JSON, a :name without a
//     value, a statement that does not fit the operation, an empty query. Mule answered 500.
//   - One statement per call (database.allowSeveralStatements switches that off).
//   - A json or jsonb column is answered as its JSON text. Mule answered an object
//     {"type", "value", "null"} with that text in "value".

import db_sys_api.core;

import ballerina/http;
import ballerina/log;
import ballerina/sql;
import ballerina/time;
import ballerinax/postgresql;

import aroya/integration_commons as commons;

// Mule: httpListener.readTimeout 120000.
listener http:Listener httpListener = new (httpPort, timeout = 120);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    log:printInfo("db-sys-api starting", env = env, basePath = basePath,
            settingsNotSet = {
                "PG_ShipTracking": core:settingsNotSet(core:KEY_SHIP_TRACKING, database, shipTracking),
                "PG_Guest": core:settingsNotSet(core:KEY_GUEST, database, guest)
            });
}

final commons:AuditSink errorRecordSink = errorRecordSinkOf();

function errorRecordSinkOf() returns commons:AuditSink {
    commons:AuditSink|error sink = commons:newAuditSink(audit);
    return sink is commons:AuditSink ? sink : new commons:NoopAuditSink();
}

isolated service class ErrorRecordedApi {
    *http:InterceptableService;

    // Mule global error handler: every failed call goes to kafka.errorTopic as
    // [saved payload, {"errorMessage": error body}] (off unless switched on in the settings)
    public function createInterceptors() returns http:Interceptor[] => commons:errorRecordInterceptors(errorRecordSink);


    // source-entry: db-system-api-flow
    // Source: ANY /db-system-api/v1/db
    isolated resource function 'default db(http:Request request) returns http:Response {
        string correlationId = commons:correlationIdOf(request);
        time:Utc started = time:utcNow();
        json|core:Refusal answer = answerOf(request, correlationId);
        decimal took = time:utcDiffSeconds(time:utcNow(), started);
        if answer is core:Refusal {
            log:printError("db call refused", correlationId = correlationId, errorType = answer.detail().errorType,
                    status = answer.detail().status, seconds = took);
            return commons:errorResponse(core:envelopeOf(answer, correlationId));
        }
        http:Response response = new;
        response.setJsonPayload(answer);
        response.setHeader(commons:CORRELATION_HEADER, correlationId);
        return response;
    }
}

final ErrorRecordedApi apiService = new;

service /health on httpListener {
    resource function get live() returns json => {status: "UP"};

    resource function get ready() returns json => {status: "UP"};
}

# Reads the request, checks it and runs the statement (Mule: db-system-api-flow and the two
# postgres sub-flows).
#
# + request - The call
# + correlationId - Its correlation id
# + return - The rows, the count of changed rows, or the refusal
isolated function answerOf(http:Request request, string correlationId) returns json|core:Refusal {
    json body = check bodyOf(request);
    core:DbRequest call = check core:requestOf(body);
    check core:checked(call);
    core:ParsedSql parsed = core:parsedOf(call.query);
    check core:statementRefusal(call.operation, parsed, database.allowSeveralStatements);
    sql:ParameterizedQuery query = check core:boundQueryOf(parsed, call.params);
    postgresql:Client db = check (call.connectionKey == core:KEY_SHIP_TRACKING ? shipTrackingPool : guestPool).clientOf();

    if call.operation == "select" {
        json[]|sql:Error rows = rowsOf(db, query);
        if rows is sql:Error {
            return failed(rows, call, correlationId);
        }
        log:printInfo("db call done", correlationId = correlationId, connectionKey = call.connectionKey,
                operation = call.operation, parameters = parsed.names.length(), rows = rows.length());
        return rows;
    }
    sql:ExecutionResult|sql:Error result = db->execute(query);
    if result is sql:Error {
        return failed(result, call, correlationId);
    }
    log:printInfo("db call done", correlationId = correlationId, connectionKey = call.connectionKey,
            operation = call.operation, parameters = parsed.names.length(), affectedRows = result.affectedRowCount);
    return core:changedOf(result.affectedRowCount);
}

isolated function rowsOf(postgresql:Client db, sql:ParameterizedQuery query) returns json[]|sql:Error {
    stream<record {}, sql:Error?> rows = db->query(query);
    json[] out = [];
    check from record {} row in rows
        do {
            out.push(core:rowOf(row));
        };
    return out;
}

// The statement and its values are never logged; the SQLSTATE says what kind of failure it was.
isolated function failed(sql:Error failure, core:DbRequest call, string correlationId) returns core:Refusal {
    log:printError("db statement failed", correlationId = correlationId, connectionKey = call.connectionKey,
            operation = call.operation, sqlState = failure is sql:DatabaseError ? failure.detail().sqlState : (),
            reason = failure is sql:DatabaseError && core:databaseRefusal(failure).detail().errorType != "CONNECTIVITY"
                ? "statement" : core:connectFailureOf(failure));
    return core:databaseRefusal(failure);
}

// No body is an empty request, as in Mule (it then fails the connection key check).
isolated function bodyOf(http:Request request) returns json|core:Refusal {
    string|http:ClientError text = request.getTextPayload();
    if text is http:ClientError || text.trim() == "" {
        return ();
    }
    json|error parsed = text.fromJsonString();
    if parsed is error {
        parsed = text.fromJsonDecimalString();
    }
    if parsed is error {
        return core:refusal("BAD_REQUEST", 400, "The request body is not JSON");
    }
    return parsed;
}
