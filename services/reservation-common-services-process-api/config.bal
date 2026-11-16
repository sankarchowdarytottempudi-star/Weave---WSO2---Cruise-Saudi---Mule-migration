import aroya/integration_commons as commons;

// reservation-common-services-process-api config (same source application as reservation-common-proc-api). Voyage/promotions lists come from the Process cache;
// other operations forward to real Seaware via the System API.
configurable string env = "vm";
configurable int httpPort = 8081;
configurable string basePath = "/${app.name}/v1";
configurable string sysApiUrl = "http://seaware-sys-api.wso2.svc";
configurable string sysApiPath = "/seaware-sys-api/v1/integration-tasks";
configurable decimal sysTimeoutSeconds = 60;
configurable string cacheUrl = "http://seaware-cache-proc-api.wso2.svc";
configurable string cachePath = "/seaware-cache-proc-api/v1/cache";
configurable decimal cacheTimeoutSeconds = 15;

# Where the old object store's values live: Redis (enabled) or memory only (enabled = false).
configurable commons:RedisSettings stateRedis = {enabled: false};

# Kafka error records of failed calls (Mule global error handler, sub-flow `kafka`). Off by default:
# while the Mule application runs, both would publish the same records.
configurable commons:AuditSettings audit = {};
