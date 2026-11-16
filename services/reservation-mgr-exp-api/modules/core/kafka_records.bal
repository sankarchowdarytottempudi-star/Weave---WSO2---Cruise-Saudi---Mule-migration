import aroya/integration_commons as commons;

// Kafka audit and error records of reservation-mgr-exp-api, field by field as the Mule
// sub-flows `savepayload` and `kafka` (global-error-handler.xml) wrote them. One change on
// purpose: Mule put the caller's bearer token into session_id, auth_token and
// request_headers.authorization in clear; here the session ids are a SHA-256 fingerprint and the
// header is "MASKED", so records still correlate per session but nobody reading the topic can
// reuse the token.

const string SOURCE_API = "reservation-mgr-exp-api";
final readonly & string[] REPLAYABLE = ["createReservation", "storeReservation", "addShorex", "addAddon",
    "CREATE_RESV", "STORE_RESV", "ADD_SHOREX", "ADD_ADDON"];

# What one request was, for its record.
#
# + correlationId - Correlation id
# + operationName - GraphQL operation name (Mule vars.operationName / x-operation-name)
# + operationType - query, mutation or subscription (Mule vars.operationType / x-operation-type)
# + clientIp - Header x-forwarded-for
# + authorization - Authorization header as sent; only its fingerprint is kept
# + targetSystem - Mule vars.targetApiName / x-target-system, "" when unknown
# + endpointUrl - Mule vars.targetUrl, else the request path
# + requestPayload - The caller's request body (Mule vars.OGPayload)
public type RecordFacts record {|
    string correlationId;
    string operationName;
    string operationType;
    string clientIp;
    string authorization;
    string targetSystem;
    string endpointUrl;
    json requestPayload;
|};

# Mule: records of query operations, and records with an empty payload, are not published.
#
# + facts - The request
# + payload - The answer (audit) or the error body (error)
# + return - True when the record is skipped
public isolated function recordSkipped(RecordFacts facts, json payload) returns boolean =>
    commons:isEmptyJson(payload) || facts.operationType.toLowerAscii() == "query";

isolated function or(string value, string fallback) returns string => value == "" ? fallback : value;

isolated function headersOf(RecordFacts f) returns json => {
    "correlationId": or(f.correlationId, "UNKNOWN"),
    "operationType": or(f.operationType, "UNKNOWN"),
    "operationName": or(f.operationName, "UNKNOWN"),
    "clientIp": or(f.clientIp, "UNKNOWN"),
    "authorization": f.authorization == "" ? "UNKNOWN" : "MASKED"
};

isolated function at(json value, string... path) returns json {
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

# The audit record of a successful request (Mule `savepayload`, topic kafka.auditTopic).
#
# + f - The request
# + response - The answer sent back
# + createdAt - Time, ISO 8601
# + return - The record
public isolated function auditRecordOf(RecordFacts f, json response, string createdAt) returns map<json> {
    boolean isLogin = f.operationName.toLowerAscii() == "login";
    json token = at(response, "data", "login", "token");
    string session = isLogin ? (token is string ? commons:tokenFingerprint(token) : "UNKNOWN")
        : commons:tokenFingerprint(f.authorization);
    return {
        "session_id": session,
        "auth_token": session,
        "mule_correlation_id": or(f.correlationId, "UNKNOWN"),
        "step_name": or(f.operationName, "UNKNOWN"),
        "source_api": SOURCE_API,
        "target_system": or(f.targetSystem, "SEAWARE"),
        "request_method": "POST",
        "endpoint_url": or(f.endpointUrl, "UNKNOWN"),
        "graphql_operation_name": f.operationName == "" ? () : f.operationName,
        "request_headers": headersOf(f),
        "request_payload": f.requestPayload ?: {},
        "response_status_code": 200,
        "response_headers": {},
        "response_payload": response ?: {},
        "status": "SUCCESS",
        "replayable": false,
        "retry_count": 0,
        "error_message": (),
        "sw_status": true,
        "created_at": createdAt
    };
}

# The error record of a failed request (Mule sub-flow `kafka`, topic kafka.errorTopic).
#
# + f - The request
# + errorBody - The error body answered
# + status - Status answered (Mule: statusCode / responseCode of the body, else the error status, else 500)
# + createdAt - Time, ISO 8601
# + return - The record
public isolated function errorRecordOf(RecordFacts f, json errorBody, int status, string createdAt) returns map<json> {
    boolean isLogin = f.operationName.toLowerAscii() == "login";
    string session = isLogin ? "UNKNOWN" : commons:tokenFingerprint(f.authorization);
    json code = at(errorBody, "statusCode") ?: at(errorBody, "responseCode");
    json message = at(errorBody, "message");
    return {
        "session_id": session,
        "auth_token": session,
        "mule_correlation_id": or(f.correlationId, "UNKNOWN"),
        "step_name": or(f.operationName, "UNKNOWN"),
        "source_api": SOURCE_API,
        "target_system": or(f.targetSystem, "SEAWARE"),
        "request_method": "POST",
        "endpoint_url": or(f.endpointUrl, "UNKNOWN"),
        "graphql_operation_name": f.operationName == "" ? () : f.operationName,
        "request_headers": headersOf(f),
        "request_payload": f.requestPayload ?: {},
        "response_status_code": code is int ? code : status,
        "response_headers": {},
        "response_payload": errorBody ?: {},
        "status": "FAILED",
        "replayable": REPLAYABLE.indexOf(f.operationName) != (),
        "retry_count": 0,
        "error_message": message is string ? message : "UNKNOWN ERROR",
        "sw_status": false,
        "created_at": createdAt
    };
}

# Mule: a query that asks for the schema is refused before anything else happens.
#
# + query - The GraphQL query text
# + return - True for IntrospectionQuery, __schema and __type
public isolated function isIntrospection(string query) returns boolean =>
    query.includes("IntrospectionQuery") || query.includes("__schema") || query.includes("__type");

# The answer Mule gave for a refused introspection query (INVALID:GRAPHQL_QUERY in Global_Error_Handler):
# status 400; it was raised before the correlation id was saved, so that is "UNKNOWN".
#
# + timestamp - Time, ISO 8601
# + return - The body
public isolated function introspectionRefusalOf(string timestamp) returns json => {
    "timestamp": timestamp,
    "statusCode": 400,
    "message": "invalid graphql query",
    "correlationId": "UNKNOWN",
    "error": "GRAPHQL_QUERY",
    "targetError": "invalid graphql query"
};

// ---- Which Kafka producer connection is used (Mule global-error-handler.xml, flows `kafka` and
// `savepayload`): when p('mule.env') == 'prod' then (p('mule.deploymentTarget') == 'ship' ?
// Apache_Kafka_Producer_configuration_prod_ship : ..._prod_shore), otherwise ..._uat.
// All three connections read p('kafka.host') ++ ':' ++ p('kafka.port') of the property file
// the application runs with (${mule.deploymentTarget}/${mule.env}.yaml).

public const string PRODUCER_UAT = "Apache_Kafka_Producer_configuration_uat";
public const string PRODUCER_PROD_SHIP = "Apache_Kafka_Producer_configuration_prod_ship";
public const string PRODUCER_PROD_SHORE = "Apache_Kafka_Producer_configuration_prod_shore";

# One Mule Kafka producer connection.
#
# + bootstrapServers - `host:port` of the brokers (Mule kafka.host:kafka.port)
public type ProducerSettings record {|
    string[] bootstrapServers = [];
|};

# The three Mule producer connections, one per target.
#
# + uat - Apache_Kafka_Producer_configuration_uat (shore/uat.yaml)
# + prodShip - Apache_Kafka_Producer_configuration_prod_ship (ship/prod.yaml)
# + prodShore - Apache_Kafka_Producer_configuration_prod_shore (shore/prod.yaml)
public type KafkaProducers record {|
    ProducerSettings uat = {};
    ProducerSettings prodShip = {};
    ProducerSettings prodShore = {};
|};

# The producer connection Mule chose for this environment and target.
#
# + muleEnv - Mule mule.env (here the service's `env` setting)
# + deploymentTarget - Mule mule.deploymentTarget: "ship" or "shore"
# + return - Name of the Mule producer connection
public isolated function producerTargetOf(string muleEnv, string deploymentTarget) returns string {
    if muleEnv == "prod" {
        return deploymentTarget == "ship" ? PRODUCER_PROD_SHIP : PRODUCER_PROD_SHORE;
    }
    return PRODUCER_UAT;
}

# The brokers of one producer connection.
#
# + producers - The three connections
# + target - Name returned by `producerTargetOf`
# + return - `host:port` list, empty when that connection has none
public isolated function serversOf(KafkaProducers producers, string target) returns string[] {
    string[] servers = target == PRODUCER_PROD_SHIP ? producers.prodShip.bootstrapServers
        : target == PRODUCER_PROD_SHORE ? producers.prodShore.bootstrapServers : producers.uat.bootstrapServers;
    return from string s in servers where s.trim() != "" select s.trim();
}

# The record settings with the brokers of the chosen connection. Brokers set directly in the
# record settings win (kept for older settings files).
#
# + settings - The `audit` settings (topics and switches)
# + producers - The three connections
# + target - Name returned by `producerTargetOf`
# + return - Settings for the record publisher
public isolated function recordSettingsOf(commons:AuditSettings settings, KafkaProducers producers, string target)
        returns commons:AuditSettings {
    if settings.bootstrapServers.length() > 0 {
        return settings;
    }
    // settings read from the configuration are read-only: build a new record, never change it
    return {bootstrapServers: serversOf(producers, target), auditTopic: settings.auditTopic,
        errorTopic: settings.errorTopic, auditEnabled: settings.auditEnabled,
        errorEnabled: settings.errorEnabled, maxBlockSeconds: settings.maxBlockSeconds};
}
