// role = "smoke": proves the Kafka settings work, with the same client code and authentication the
// worker uses. Read-only unless smokeTestTopic is set (owner approval). Prints counts and yes/no
// answers only: no broker address, user, secret or message body.

import ballerina/io;
import ballerina/uuid;
import ballerinax/kafka;

isolated function smokeLine(string what, boolean ok, string detail = "") {
    io:println(string `SMOKE kafka ${what}: ${ok ? "OK" : "FAILED"}${detail == "" ? "" : " - " + detail}`);
}

# Runs the Kafka smoke test.
#
# + s - Kafka settings
# + testTopic - Test topic for a write/read round trip; "" = read-only
# + return - An error when any check failed
isolated function runKafkaSmoke(KafkaSettings s, string testTopic) returns error? {
    if s.bootstrapServers.length() == 0 {
        smokeLine("settings", false, "kafkaConfig.bootstrapServers is empty");
        return error("Kafka is not set");
    }
    kafka:ConsumerConfiguration c = {
        groupId: s.consumerGroup + "-smoke",
        clientId: s.clientId + "-smoke",
        autoCommit: false,
        securityProtocol: check protocolOf(s.securityProtocol)
    };
    kafka:AuthenticationConfiguration? auth = check authOf(s);
    if auth is kafka:AuthenticationConfiguration {
        c.auth = auth;
    }
    if s.caCertPath != "" {
        c.secureSocket = {cert: s.caCertPath};
    }
    kafka:Consumer|kafka:Error consumer = new (s.bootstrapServers, c);
    if consumer is kafka:Error {
        smokeLine("client", false, consumer.message());
        return consumer;
    }
    int failures = 0;
    string[]|kafka:Error topics = consumer->getAvailableTopics(30);
    if topics is kafka:Error {
        smokeLine("broker metadata (authentication, TLS, network)", false, topics.message());
        failures += 1;
    } else {
        smokeLine("broker metadata (authentication, TLS, network)", true, topics.length().toString() + " topics visible");
        foreach string t in [s.evaluationTopic, s.reevaluationTopic, s.dlqTopic] {
            boolean present = topics.indexOf(t) is int;
            kafka:TopicPartition[]|kafka:Error parts = [];
            if present {
                parts = consumer->getTopicPartitions(t, 30);
            }
            smokeLine("topic " + t, present && parts is kafka:TopicPartition[],
                        present ? (parts is kafka:TopicPartition[] ? parts.length().toString() + " partitions" : parts.message())
                        : "not found (create it, or grant DESCRIBE)");
            if !present || parts is kafka:Error {
                failures += 1;
            }
        }
    }
    if testTopic != "" {
        error? roundTrip = smokeRoundTrip(s, consumer, testTopic);
        smokeLine("write/read round trip on the approved test topic", roundTrip is (),
                    roundTrip is error ? roundTrip.message() : "");
        if roundTrip is error {
            failures += 1;
        }
    } else {
        smokeLine("write/read round trip", true, "skipped (no approved test topic; nothing was written)");
    }
    error? closed = consumer->close();
    if failures > 0 {
        return error(failures.toString() + " Kafka check(s) failed");
    }
    return closed is error ? () : ();
}

isolated function smokeRoundTrip(KafkaSettings s, kafka:Consumer consumer, string topic) returns error? {
    kafka:TopicPartition[] parts = check consumer->getTopicPartitions(topic, 30);
    check consumer->assign(parts);
    check consumer->seekToEnd(parts);
    foreach kafka:TopicPartition p in parts {
        _ = check consumer->getPositionOffset(p, 30); // pins the end position before writing
    }
    EventBus bus = check new KafkaBus(s);
    string marker = uuid:createType4AsString();
    check bus.publish(topic, "smoke", {smoke: marker});
    foreach int _ in 1 ... 10 {
        kafka:BytesConsumerRecord[] got = check consumer->poll(3);
        foreach kafka:BytesConsumerRecord r in got {
            string|error v = string:fromBytes(r.value);
            if v is string && v.includes(marker) {
                return;
            }
        }
    }
    return error("the test message was written but not read back within 30 s");
}
