import aroya/integration_commons as commons;

// reservation-common-proc-api config. Voyage/promotions lists come from the Process cache;
// other operations forward to real Seaware via the System API.
configurable string env = "vm";
configurable int httpPort = 8081;
configurable string basePath = "/reservation-common-proc-api/v1";
configurable string sysApiUrl = "http://seaware-sys-api.wso2.svc";
configurable string sysApiPath = "/seaware-sys-api/v1/integration-tasks";
configurable decimal sysTimeoutSeconds = 60;
configurable string cacheUrl = "http://seaware-cache-proc-api.wso2.svc";
configurable string cachePath = "/seaware-cache-proc-api/v1/cache";
configurable decimal cacheTimeoutSeconds = 15;
// Payments are handled by the financial transactions Process API (inside the cluster).
configurable string paymentsUrl = "http://financial-transactions-proc-api.wso2.svc";
configurable string paymentsPath = "/financial-transactions-proc-api/v1/process-payment";
configurable decimal paymentsTimeoutSeconds = 60;

# Kafka error records of failed calls (Mule global error handler, sub-flow `kafka`). Off by default:
# while the Mule application runs, both would publish the same records.
configurable commons:AuditSettings audit = {};
