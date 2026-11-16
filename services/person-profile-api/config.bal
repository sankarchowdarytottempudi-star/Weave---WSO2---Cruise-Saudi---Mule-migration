import aroya/integration_commons as commons;

// Settings of person-profile-api, ported by hand from the Mule application person-profile-proc-api.
// Values per environment: deploy/vm/config/person-profile-api.toml (taken from shore/uat.yaml).

configurable string env = ?;
configurable int httpPort = 8081;
# Address the service listens on. All addresses by default; the tests listen on this machine only.
configurable string httpHost = "0.0.0.0";
# Mule listener path `${app.name}/v1/*` (the OAS server URL /person-profile-proc-api/v1/).
configurable string basePath = "/person-profile-proc-api/v1";

# Otalio System API, the only backend of this API. Mule: HTTP_Request_configuration
# (`personprofileConfigDetails.host`, `.port`, protocol HTTPS; `.responseTime` as the timeout).
configurable commons:DownstreamSettings otalioSystemApi = {url: "http://localhost"};

# Mule `personprofileConfigDetails.path`: the one path every call goes to.
configurable string otalioPath = "/otalio-sys-api-new/v1/integration-tasks";

# Mule `error.httpRetryCount`: how often a call that failed with one of `httpErrorTypes` is repeated.
configurable int httpRetryCount = 0;
# Mule `error.httpRetryFrequency` / 1000: pause before a repeat.
configurable decimal httpRetryFrequencySeconds = 5;
# Mule `error.httpErrorTypes`.
configurable string[] httpErrorTypes = ["CONNECTIVITY", "TIMEOUT"];

# Kafka error records (Mule `kafka.*`, Apache_Kafka_Producer_configuration; only the error record
# is used: the audit sub-flow `savepayload` is never called in the old application).
configurable commons:AuditSettings audit = {};
