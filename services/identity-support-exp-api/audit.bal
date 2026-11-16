import identity_support_exp_api.core;

import ballerina/http;
import ballerina/lang.array;
import ballerina/log;
import ballerina/time;
import ballerinax/kafka;
import aroya/integration_commons as commons;

// Audit records, error records and the error e-mail, as the Mule application had them
// (global-error-handler.xml: savepayload, kafka; email-Notification.xml). Off until switched on
// in the settings: while the Mule application still runs, both would write the same records.

# Kafka records of every call (Mule kafka.*).
#
# + enabled - Master switch (off by default)
# + muleEnv - Mule mule.env: "prod" chooses a prod producer, anything else the uat one
# + deploymentTarget - Mule mule.deploymentTarget: "ship" or "shore" (with mule.env = prod)
# + auditTopic - Mule kafka.auditTopic
# + errorTopic - Mule kafka.errorTopic
# + auditPayloads - Mule kafka.AuditPayloadToKafka
# + errorPayloads - Mule kafka.ErrorPayloadToKafka
type KafkaAuditSettings record {|
    boolean enabled = false;
    string muleEnv = "uat";
    string deploymentTarget = "shore";
    string auditTopic = "";
    string errorTopic = "";
    boolean auditPayloads = true;
    boolean errorPayloads = true;
|};

# Error e-mail through the e-mail system API (Mule internal-sys-exp-api-exceptionSub_Flow).
#
# + enabled - Switch (off by default)
# + url - Address of the e-mail system API (Mule HTTP_Request_configuration_internal)
# + path - Mule httpRequest.internal.emailNotificationPath
# + toAddress - Mule email.toAddress
# + ccAddress - Mule email.ccAddress
# + app - Mule app (subject)
# + env - Mule mule.env (subject); empty = the service's env setting
# + timeoutSeconds - Mule httpRequest.responseTimeOut
type ErrorMailSettings record {|
    boolean enabled = false;
    string url = "";
    string path = "/email-sys-api/v1/send-email-notification";
    string toAddress = "";
    string ccAddress = "";
    string app = "identity-support-exp-api";
    string env = "";
    decimal timeoutSeconds = 30;
|};

# One producer connection of the Mule application.
#
# + bootstrapServers - host:port[,host:port]
type KafkaProducerSettings record {|
    string bootstrapServers = "";
|};

# The three producer connections of the Mule application (global-config.xml), each from the property
# file of its target.
#
# + uat - Apache_Kafka_Producer_configuration_uat: kafka.host:kafka.port
# + prodShip - Apache_Kafka_Producer_configuration_prod_ship: kafka.host:kafka.port (ship/prod.yaml)
# + prodShore - Apache_Kafka_Producer_configuration_prod_shore: kafka, kafka1 and kafka2 host:port (shore/prod.yaml)
type KafkaProducersSettings record {|
    KafkaProducerSettings uat = {};
    KafkaProducerSettings prodShip = {};
    KafkaProducerSettings prodShore = {};
|};

configurable KafkaAuditSettings kafkaAudit = {};
configurable KafkaProducersSettings kafkaProducers = {};
configurable ErrorMailSettings errorMail = {};

final kafka:Producer? auditProducer = producerOf();
final http:Client? mailClient = mailClientOf();

function serversOf(string target) returns string {
    match target {
        core:PRODUCER_PROD_SHIP => {
            return kafkaProducers.prodShip.bootstrapServers.trim();
        }
        core:PRODUCER_PROD_SHORE => {
            return kafkaProducers.prodShore.bootstrapServers.trim();
        }
    }
    return kafkaProducers.uat.bootstrapServers.trim();
}

function producerOf() returns kafka:Producer? {
    string target = core:producerTargetOf(kafkaAudit.muleEnv, kafkaAudit.deploymentTarget);
    string servers = serversOf(target);
    // which connection is used, never its address
    log:printInfo("Kafka records", state = kafkaAudit.enabled ? (servers == "" ? "on, but the connection has no address" : "on") : "off",
            producer = target, muleEnv = kafkaAudit.muleEnv, deploymentTarget = kafkaAudit.deploymentTarget);
    if !kafkaAudit.enabled || servers == "" {
        return ();
    }
    kafka:Producer|kafka:Error made = new (re `\s*,\s*`.split(servers),
        clientId = "identity-support-exp-api", acks = kafka:ACKS_SINGLE, requestTimeout = 10, maxBlock = 5);
    if made is kafka:Error {
        log:printError("Kafka records are switched on but the producer could not be made", 'error = made);
        return ();
    }
    return made;
}

function mailClientOf() returns http:Client? {
    if !errorMail.enabled || core:isPlaceholderAddress(errorMail.url) {
        return ();
    }
    http:Client|http:ClientError made = new (errorMail.url, {timeout: errorMail.timeoutSeconds});
    if made is http:ClientError {
        log:printError("Error e-mails are switched on but the client could not be made", 'error = made);
        return ();
    }
    return made;
}

isolated function payloadOf(byte[] raw) returns json {
    if raw.length() == 0 {
        return {};
    }
    string|error text = string:fromBytes(raw);
    if text is error {
        return {};
    }
    json|error parsed = text.fromJsonString();
    return parsed is json ? parsed : text;
}

# Records one call: its audit record, or its error record and error e-mail. Never changes the answer.
#
# + path - Path of the operation below the base path
# + request - The caller's request
# + answer - The answer sent back
# + correlationId - Correlation id
isolated function recordCall(string path, http:Request request, http:Response answer, string correlationId) {
    if auditProducer is () && mailClient is () {
        return;
    }
    // On the request path only what must be read before the answer leaves: the two bodies (already
    // in memory) and four headers. Parsing, building the records, Kafka and the e-mail run apart,
    // so they never add to the caller's wait (Mule: async scope).
    byte[]|http:ClientError inRaw = request.getBinaryPayload();
    byte[]|http:ClientError outRaw = answer.getBinaryPayload();
    CallCapture capture = {
        path,
        correlationId,
        status: answer.statusCode,
        operationName: commons:headerOf(request, "x-operation-name"),
        operationType: commons:headerOf(request, "x-operation-type") ?: "",
        clientIp: commons:headerOf(request, "x-forwarded-for") ?: "",
        authorization: commons:headerOf(request, "Authorization") ?: commons:headerOf(request, "client_authorization") ?: "",
        inRaw: inRaw is byte[] ? inRaw.cloneReadOnly() : [],
        outRaw: outRaw is byte[] ? outRaw.cloneReadOnly() : []
    };
    future<()> _ = start recordCaptured(capture.cloneReadOnly());
}

# What `recordCall` keeps of one call for the work done after the answer.
type CallCapture record {|
    string path;
    string correlationId;
    int status;
    string? operationName;
    string operationType;
    string clientIp;
    string authorization;
    byte[] inRaw;
    byte[] outRaw;
|};

isolated function recordCaptured(CallCapture & readonly c) {
    core:CallFacts facts = {
        correlationId: c.correlationId,
        operationName: core:operationNameOf(c.operationName, c.path),
        operationType: c.operationType,
        clientIp: c.clientIp,
        authorization: c.authorization,
        endpoint: c.path,
        requestPayload: payloadOf(c.inRaw)
    };
    json answerPayload = payloadOf(c.outRaw);
    string now = time:utcToString(time:utcNow());
    int status = c.status;
    string correlationId = c.correlationId;
    if status < 400 {
        if core:isEmptyPayload(answerPayload) {
            log:printWarn("Payload is empty, skipping Kafka publish", correlationId = correlationId);
        } else if kafkaAudit.auditPayloads {
            publish(kafkaAudit.auditTopic, correlationId, core:auditRecordOf(facts, answerPayload, now).cloneReadOnly());
        }
        return;
    }
    string errorType = core:errorTypeOfStatus(status);
    string description = answerPayload is map<json> && answerPayload["message"] is string
        ? <string>answerPayload["message"] : "The call answered " + status.toString();
    if core:isEmptyPayload(answerPayload) {
        log:printWarn("Payload is empty, skipping Kafka publish", correlationId = correlationId);
    } else if kafkaAudit.errorPayloads {
        // Kafka and the e-mail do not wait for each other (both were async in Mule).
        future<()> _ = start publish(kafkaAudit.errorTopic, correlationId,
                core:errorRecordOf(facts, status, answerPayload, description, now).cloneReadOnly());
    }
    string details = answerPayload is string ? answerPayload : answerPayload.toJsonString();
    sendErrorMail(errorType, description, details, correlationId);
}

isolated function publish(string topic, string key, map<json> & readonly rec) {
    kafka:Producer? producer = auditProducer;
    if producer is () || topic == "" {
        return;
    }
    kafka:Error? sent = producer->send({topic, key: key.toBytes(), value: rec.toJsonString().toBytes()});
    if sent is kafka:Error {
        log:printWarn("Kafka record not sent", correlationId = key, topic = topic, reason = sent.message());
    }
}

isolated function sendErrorMail(string errorType, string description, string details, string correlationId) {
    http:Client? mails = mailClient;
    if mails is () {
        return;
    }
    json body = core:errorMailOf(errorMail.env == "" ? env : errorMail.env, errorMail.app, errorType, description,
            details, errorMail.toAddress, errorMail.ccAddress, array:toBase64(details.toBytes()));
    http:Response|http:ClientError sent = mails->post(errorMail.path, body, {[commons:CORRELATION_HEADER]: correlationId});
    if sent is http:ClientError {
        log:printWarn("Error e-mail not sent", correlationId = correlationId, reason = sent.message());
    } else if sent.statusCode >= 300 {
        log:printWarn("Error e-mail refused", correlationId = correlationId, status = sent.statusCode);
    }
}
