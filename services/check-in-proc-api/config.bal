import aroya/integration_commons as commons;

// Settings of check-in-proc-api, ported by hand from the Mule application.
// Values per environment: deploy/vm/config/check-in-proc-api.toml.

configurable string env = ?;
configurable int httpPort = 8081;
# Address the service listens on. All addresses by default; the tests listen on this machine only.
configurable string httpHost = "0.0.0.0";
configurable string basePath = "/check-in-proc-api/v1";

# Otalio System API: the only backend of this API. Mule: HTTP_Request_configuration
# (`httpRequest.host`, `httpRequest.port`, `httpRequest.responseTime`).
configurable commons:DownstreamSettings otalioSystemApi = {url: "http://localhost"};

# Base path of the Otalio System API; the paths below are added to it.
configurable string otalioBasePath = "/otalio-sys-api-new/v1";

# Mule `httpRequest.path.<name>`: the path of each call, which may carry its own query string.
# Only the names that differ from the built-in paths (core:DEFAULT_PATHS) need a value.
configurable map<string> otalioPaths = {};

# Mule `error.httpRetryCount`: how often a call that failed with one of `httpErrorTypes` is repeated.
configurable int httpRetryCount = 0;
# Mule `error.httpRetryFrequency` / 1000: pause before a repeat.
configurable decimal httpRetryFrequencySeconds = 5;
# Mule `error.httpErrorTypes`.
configurable string[] httpErrorTypes = ["BAD_GATEWAY", "CONNECTIVITY", "TIMEOUT"];

# Kafka error records (Mule `kafka.*`; only `errorEnabled`, `errorTopic` and `bootstrapServers`
# are used: this application never called the audit sub-flow).
configurable commons:AuditSettings audit = {};
