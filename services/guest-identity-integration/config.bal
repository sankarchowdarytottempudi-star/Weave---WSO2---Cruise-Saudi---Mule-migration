// Settings of guest-identity-integration (plan v2.1 sections 10, 11, 14, 17).
// One image, three roles: the identity worker, the review API and the nightly reconciliation.
// Kafka and the CRM are reached only with what is set here; nothing has a production default.

import guest_identity_integration.core;

import aroya/integration_commons as commons;

configurable string env = "local";
configurable int httpPort = 8081;
configurable string httpHost = "0.0.0.0";
configurable string basePath = "/guest-identity-integration/v1";

# worker | review | reconcile | all. worker: consumes the evaluation topics; review: the Review API
# and the CRM webhook; reconcile: runs once and exits (the nightly CronJob); all: worker + review.
configurable string role = "review";

# Kafka (the customer's existing cluster). Empty bootstrapServers = Kafka not set: the worker does
# not start, the webhook and ingress answer 503 for publishing, and nothing else changes.
#
# + bootstrapServers - host:port list
# + securityProtocol - PLAINTEXT | SASL_PLAINTEXT | SASL_SSL | SSL
# + saslMechanism - PLAIN | SCRAM-SHA-256 | SCRAM-SHA-512 (with a SASL protocol)
# + username - SASL user
# + password - SASL password
# + caCertPath - CA certificate (PEM) of the brokers, for SSL / SASL_SSL; empty = the JVM's trust store
# + consumerGroup - Consumer group of the identity worker
# + evaluationTopic - Evaluation topic
# + reevaluationTopic - Re-evaluation topic
# + dlqTopic - Dead-letter topic
# + pollSeconds - Longest wait of one poll
# + maxPollRecords - Records taken per poll (kept small: a record may wait for retries)
# + maxPollIntervalMs - Longest time between polls before the broker gives the partitions away
# + clientId - Client id shown to the brokers
public type KafkaSettings record {|
    string[] bootstrapServers = [];
    string securityProtocol = "SASL_SSL";
    string saslMechanism = "SCRAM-SHA-512";
    string username = "";
    string password = "";
    string caCertPath = "";
    string consumerGroup = "guest-identity-worker";
    string evaluationTopic = "guest.identity.evaluation.requested.v1";
    string reevaluationTopic = "guest.identity.reevaluation.requested.v1";
    string dlqTopic = "guest.identity.processing.dlq.v1";
    decimal pollSeconds = 5;
    int maxPollRecords = 10;
    int maxPollIntervalMs = 900000;
    string clientId = "guest-identity-integration";
|};

configurable KafkaSettings kafkaConfig = {};

# The Python Guest Identity Decision API (in our integration cluster), and its service token.
configurable commons:DownstreamSettings python = {url: "http://localhost"};
configurable string pythonServiceToken = "";

# Zoho CRM, through zoho-sys-api (it holds the Zoho account and token).
configurable commons:DownstreamSettings zohoSysApi = {url: "http://localhost"};
configurable string zohoSystemPath = "/zoho-sys-api/v1/zoho";
configurable string crmApiVersion = "v6";

# Retries of one event (worker) and of one call (commit, CRM write).
#
# + maxAttempts - Attempts before the event goes to the DLQ
# + firstBackoffSeconds - Wait after the first failure; doubles each time
# + maxBackoffSeconds - Longest wait
public type RetrySettings record {|
    int maxAttempts = 5;
    decimal firstBackoffSeconds = 2;
    decimal maxBackoffSeconds = 60;
|};

configurable RetrySettings retries = {};

# Reviewer authentication: the Workbench backend signs the CRM user context (see README).
#
# + serviceToken - Bearer token of the Workbench backend (Factory BFF REVIEW_API_TOKEN_FILE); the
# reviewer then comes from its x-reviewer-id / x-reviewer-roles headers. Empty = off
# + signingSecret - Shared HMAC secret for a signed reviewer context (alternative); empty = off
# + maxAgeSeconds - Longest lifetime of a signed context
public type ReviewAuthSettings record {|
    string serviceToken = "";
    string signingSecret = "";
    int maxAgeSeconds = 300;
|};

configurable ReviewAuthSettings reviewAuth = {};

# Token the CRM workflow webhook sends in X-Webhook-Token; empty = the webhook answers 503.
configurable string webhookToken = "";

# Nightly reconciliation (plan 17).
#
# + pageSize - Records per CRM query (COQL allows at most 2000)
# + maxPages - Pages read per query before the run stops (the watermark is then not advanced)
# + pendingAfterMinutes - A Guest PENDING_IDENTITY for longer than this is republished
# + initialWatermark - Watermark used when none is stored (CRM date-time)
# + lockSeconds - Lifetime of the single-run lock
# + stateKeyPrefix - Redis key prefix of the lock and the watermark
public type ReconcileSettings record {|
    int pageSize = 2000;
    int maxPages = 50;
    int pendingAfterMinutes = 60;
    string initialWatermark = "2026-01-01T00:00:00+00:00";
    int lockSeconds = 3600;
    string stateKeyPrefix = "gir:reconcile:";
|};

configurable ReconcileSettings reconcile = {};

# Redis for the reconciliation lock and watermark. enabled = false: kept in memory (one run only;
# only for tests - the reconciliation then refuses to run unless allowMemoryState is set).
configurable commons:RedisSettings stateRedis = {enabled: false};
configurable boolean allowMemoryState = false;

# The approved direct scope (owner decision), and the CRM field / module API names.
configurable core:DirectScope directScope = {};
configurable core:CrmFields crmFields = {};
configurable core:CrmModules crmModules = {};

# role = "smoke": a one-off connectivity check of the Kafka settings (broker metadata and the three
# topics; read-only). A test topic is written to and read back ONLY when one is named here, which
# needs the owner's approval; "" = nothing is written anywhere.
configurable string smokeTestTopic = "";
