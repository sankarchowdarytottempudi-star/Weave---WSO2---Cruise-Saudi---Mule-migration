import ballerina/log;
import ballerinax/kafka;

// Audit and error events, replacing the `savepayload` and `kafka` sub-flows. The record
// layout is the one the downstream audit consumer reads today: the original request followed
// by the response (audit) or the error body (error).

# Kafka settings for audit and error events.
#
# + bootstrapServers - `host:port` list (Mule `kafka.host`/`kafka.port`, plus `kafka1`/`kafka2` on shore prod)
# + auditTopic - Topic for successful requests (Mule `kafka.auditTopic`)
# + errorTopic - Topic for failed requests (Mule `kafka.errorTopic`)
# + auditEnabled - Mule `kafka.AuditPayloadToKafka`
# + errorEnabled - Mule `kafka.ErrorPayloadToKafka`
# + maxBlockSeconds - How long a send may block (Mule `kafka.maximumBlockTimeMs` / 1000)
public type AuditSettings record {|
    string[] bootstrapServers = [];
    string auditTopic = "";
    string errorTopic = "";
    boolean auditEnabled = false;
    boolean errorEnabled = false;
    decimal maxBlockSeconds = 5;
|};

# Where audit and error events go. Services depend on this type, not on Kafka, so tests use
# the no-op sink and another broker can be added without touching a service.
public type AuditSink isolated object {
    # Publishes an audit event for a successful request.
    #
    # + correlationId - Record key
    # + request - The original request body
    # + response - The response body
    public isolated function audit(string correlationId, json request, json response);

    # Publishes an error event for a failed request.
    #
    # + correlationId - Record key
    # + request - The original request body
    # + errorBody - The error body returned to the caller
    public isolated function failure(string correlationId, json request, json errorBody);
};

# A sink that drops everything (Kafka disabled, tests).
public isolated distinct class NoopAuditSink {
    *AuditSink;

    public isolated function audit(string correlationId, json request, json response) {
    }

    public isolated function failure(string correlationId, json request, json errorBody) {
    }
}

# Kafka sink. Failures are logged and never reach the caller (Mule: on-error-continue).
public isolated class KafkaAuditSink {
    *AuditSink;

    private final kafka:Producer producer;
    private final AuditSettings & readonly settings;

    # + settings - Kafka settings
    # + return - An error if the producer cannot be created
    public isolated function init(AuditSettings settings) returns error? {
        self.settings = settings.cloneReadOnly();
        self.producer = check new (settings.bootstrapServers, {
            maxBlock: settings.maxBlockSeconds,
            acks: kafka:ACKS_SINGLE
        });
    }

    public isolated function audit(string correlationId, json request, json response) {
        // Mule `savepayload`: publishes the payload as it is, skipped when it is empty
        if self.settings.auditEnabled {
            if isEmptyJson(response) {
                log:printWarn("Payload is empty, skipping Kafka publish", correlationId = correlationId);
                return;
            }
            self.send(self.settings.auditTopic, correlationId, response);
        }
    }

    # + return - Whether error records are switched on
    public isolated function errorsOn() returns boolean => self.settings.errorEnabled;

    public isolated function failure(string correlationId, json request, json errorBody) {
        if self.settings.errorEnabled {
            // Mule `kafka`: skipped when the error body or the saved payload is empty, else
            // [vars.OGPayload] ++ [{"errorMessage": payload}]
            if isEmptyJson(request) || isEmptyJson(errorBody) {
                log:printWarn("Payload is empty, skipping Kafka publish", correlationId = correlationId);
                return;
            }
            self.send(self.settings.errorTopic, correlationId, [request, {errorMessage: errorBody}]);
        }
    }

    private isolated function send(string topic, string correlationId, json value) {
        kafka:Error? sent = self.producer->send({
            topic,
            key: correlationId.toBytes(),
            value: value.toJsonString().toBytes()
        });
        if sent is kafka:Error {
            log:printError("Kafka publish failed", topic = topic, correlationId = correlationId, 'error = sent);
        }
    }
}

# Creates the sink the settings ask for.
#
# + settings - Kafka settings
# + return - A Kafka sink when either kind of event is enabled, otherwise a no-op sink
public isolated function newAuditSink(AuditSettings settings) returns AuditSink|error {
    if (settings.auditEnabled || settings.errorEnabled) && settings.bootstrapServers.length() > 0 {
        KafkaAuditSink|error sink = new (settings);
        if sink is error {
            // a broker that cannot be set up never stops the service (Mule: on-error-continue)
            log:printError("Kafka records are switched on but the producer could not be made", 'error = sink);
            return new NoopAuditSink();
        }
        return sink;
    }
    return new NoopAuditSink();
}

# Mule `isEmpty`: null, "", [] and {} are empty.
#
# + value - Any JSON value
# + return - True when empty
public isolated function isEmptyJson(json value) returns boolean {
    if value is () {
        return true;
    }
    if value is string {
        return value.length() == 0;
    }
    if value is json[] {
        return value.length() == 0;
    }
    if value is map<json> {
        return value.length() == 0;
    }
    return false;
}
