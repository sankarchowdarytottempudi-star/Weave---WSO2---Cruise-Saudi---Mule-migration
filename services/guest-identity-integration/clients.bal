// The three things this service talks to, each behind an object type so tests use stand-ins:
// the Python decision API, the CRM (through zoho-sys-api) and the event bus (Kafka).

import ballerina/http;
import ballerina/log;
import ballerinax/kafka;

import aroya/integration_commons as commons;

# A reply of an HTTP backend.
#
# + status - HTTP status
# + body - JSON body; () when empty or not JSON
public type Reply record {|
    int status;
    json body;
|};

# The Python Guest Identity Decision API.
public type PythonApi isolated object {
    # One call.
    #
    # + method - GET or POST
    # + path - Path below the API root, e.g. /v1/guest-identities/evaluate
    # + body - Body for POST
    # + correlationId - Correlation id (X-Correlation-Id)
    # + headers - Extra headers (reviewer headers)
    # + return - The reply, or an error when the API could not be reached
    isolated function call(string method, string path, json body, string correlationId,
            map<string> headers = {}) returns Reply|error;
};

# Zoho CRM through zoho-sys-api.
public type CrmApi isolated object {
    # One CRM call.
    #
    # + method - GET, POST or PUT
    # + zohoPath - CRM path, e.g. /crm/v6/Contacts
    # + query - Query parameters
    # + body - Body for POST / PUT
    # + correlationId - Correlation id
    # + return - The reply, or an error when zoho-sys-api could not be reached
    isolated function call(string method, string zohoPath, map<string> query, json body, string correlationId)
            returns Reply|error;
};

# The event bus.
public type EventBus isolated object {
    # Publishes one event, keyed by the CRM Guest record id (one partition per Guest keeps its
    # events in order).
    #
    # + topic - Topic
    # + key - Partition key
    # + event - Event
    # + return - An error when the event was not accepted
    isolated function publish(string topic, string key, map<json> event) returns error?;
};

isolated function replyOf(http:Response|http:ClientError r) returns Reply|error {
    if r is http:ClientError {
        return r;
    }
    json|http:ClientError body = r.getJsonPayload();
    return {status: r.statusCode, body: body is json ? body : ()};
}

isolated class HttpPython {
    *PythonApi;
    private final http:Client 'client;
    private final string token;

    isolated function init(commons:DownstreamSettings settings, string token) returns error? {
        self.'client = check commons:newDownstreamClient(settings);
        self.token = token;
    }

    isolated function call(string method, string path, json body, string correlationId,
            map<string> headers = {}) returns Reply|error {
        map<string> h = {...headers};
        h["X-Correlation-Id"] = correlationId;
        if self.token != "" {
            h["Authorization"] = "Bearer " + self.token;
        }
        http:Response|http:ClientError r;
        if method == http:GET {
            r = self.'client->get(path, h);
        } else {
            r = self.'client->post(path, body, h, mediaType = "application/json");
        }
        return replyOf(r);
    }
}

isolated class HttpCrm {
    *CrmApi;
    private final http:Client 'client;
    private final string systemPath;

    isolated function init(commons:DownstreamSettings settings, string systemPath) returns error? {
        self.'client = check commons:newDownstreamClient(settings);
        self.systemPath = systemPath;
    }

    isolated function call(string method, string zohoPath, map<string> query, json body, string correlationId)
            returns Reply|error {
        map<string> h = {"zohoPath": zohoPath};
        h[commons:CORRELATION_HEADER] = correlationId;
        string path = self.systemPath + queryOf(query);
        http:Response|http:ClientError r;
        if method == http:GET {
            r = self.'client->get(path, h);
        } else if method == http:PUT {
            r = self.'client->put(path, body, h, mediaType = "application/json");
        } else {
            r = self.'client->post(path, body, h, mediaType = "application/json");
        }
        Reply reply = check replyOf(r);
        // Zoho answers 204 without a body when nothing matches.
        return reply.status == 204 ? {status: 200, body: {"data": []}} : reply;
    }
}

isolated function queryOf(map<string> query) returns string {
    string out = "";
    foreach [string, string] [k, v] in query.entries() {
        string|error e = encode(v);
        out += (out == "" ? "?" : "&") + k + "=" + (e is string ? e : v);
    }
    return out;
}

isolated function encode(string v) returns string|error {
    // URL encoding without importing ballerina/url everywhere
    string out = "";
    foreach string c in v {
        int cp = c.getCodePoint(0);
        if (cp >= 48 && cp <= 57) || (cp >= 65 && cp <= 90) || (cp >= 97 && cp <= 122) || c == "-" || c == "_"
                || c == "." || c == "~" {
            out += c;
        } else {
            foreach byte b in c.toBytes() {
                string hex = b.toHexString().toUpperAscii();
                out += "%" + (hex.length() == 1 ? "0" + hex : hex);
            }
        }
    }
    return out;
}

# Kafka not set: every publish fails with KAFKA_NOT_CONFIGURED (callers answer 503 / keep PENDING
# for the reconciliation), nothing is sent anywhere.
isolated class NoBus {
    *EventBus;

    isolated function publish(string topic, string key, map<json> event) returns error? {
        return error("KAFKA_NOT_CONFIGURED");
    }
}

# The real bus: one idempotent producer (acks=all), SASL/SCRAM or TLS from the settings.
isolated class KafkaBus {
    *EventBus;
    private final kafka:Producer producer;

    isolated function init(KafkaSettings s) returns error? {
        kafka:ProducerConfiguration c = {
            clientId: s.clientId,
            acks: kafka:ACKS_ALL,
            enableIdempotence: true,
            retryCount: 5,
            securityProtocol: check protocolOf(s.securityProtocol)
        };
        kafka:AuthenticationConfiguration? auth = check authOf(s);
        if auth is kafka:AuthenticationConfiguration {
            c.auth = auth;
        }
        if s.caCertPath != "" {
            c.secureSocket = {cert: s.caCertPath};
        }
        self.producer = check new (s.bootstrapServers, c);
    }

    isolated function publish(string topic, string key, map<json> event) returns error? {
        check self.producer->send({topic, key: key.toBytes(), value: event.toJsonString().toBytes()});
        check self.producer->'flush();
    }
}

isolated function protocolOf(string p) returns kafka:SecurityProtocol|error {
    match p.toUpperAscii() {
        "PLAINTEXT" => {
            return kafka:PROTOCOL_PLAINTEXT;
        }
        "SASL_PLAINTEXT" => {
            return kafka:PROTOCOL_SASL_PLAINTEXT;
        }
        "SASL_SSL" => {
            return kafka:PROTOCOL_SASL_SSL;
        }
        "SSL" => {
            return kafka:PROTOCOL_SSL;
        }
    }
    return error("kafka.securityProtocol must be PLAINTEXT, SASL_PLAINTEXT, SASL_SSL or SSL");
}

isolated function authOf(KafkaSettings s) returns kafka:AuthenticationConfiguration?|error {
    if !s.securityProtocol.toUpperAscii().startsWith("SASL") {
        return ();
    }
    if s.username == "" || s.password == "" {
        return error("kafka.username and kafka.password are required with a SASL protocol");
    }
    kafka:AuthenticationMechanism mechanism = kafka:AUTH_SASL_PLAIN;
    match s.saslMechanism.toUpperAscii() {
        "PLAIN" => {
            mechanism = kafka:AUTH_SASL_PLAIN;
        }
        "SCRAM-SHA-256" => {
            mechanism = kafka:AUTH_SASL_SCRAM_SHA_256;
        }
        "SCRAM-SHA-512" => {
            mechanism = kafka:AUTH_SASL_SCRAM_SHA_512;
        }
        _ => {
            return error("kafka.saslMechanism must be PLAIN, SCRAM-SHA-256 or SCRAM-SHA-512");
        }
    }
    return {mechanism, username: s.username, password: s.password};
}

# The bus of the settings: Kafka when bootstrap servers are set, otherwise NoBus.
isolated function busOf(KafkaSettings s) returns EventBus {
    if s.bootstrapServers.length() == 0 {
        log:printWarn("Kafka is not set: events are not published (kafka.bootstrapServers is empty)");
        return new NoBus();
    }
    KafkaBus|error bus = new (s);
    if bus is error {
        log:printError("Kafka producer could not be created: events are not published", reason = bus.message());
        return new NoBus();
    }
    return bus;
}
