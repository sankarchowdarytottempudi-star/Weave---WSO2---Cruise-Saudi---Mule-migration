import aroya/integration_commons as commons;
import reservation_mgr_exp_api.core;

// Configuration. Every Mule property of src/main/resources/{shore,ship}/{env}.yaml has a
// place here; the mapping is in docs/generated/reservation-mgr-exp-api/MAPPING.md.

# Settings of the asynchronous request path (`client_asyncFlag: true`).
#
# + connectionKey - db-sys-api connection key (Mule `PG_Guest`)
# + table - Status table (Mule `cs_mule_framework.cs_async_req_status`)
# + description - Value written to `description` (Mule `p("app.name")`)
# + statusUpdateAttempts - Attempts for each status update (Mule `until-successful.maxRetries` + 1)
# + statusUpdateIntervalSeconds - Wait between them (Mule `until-successful.millisBetweenRetries` / 1000)
type AsyncSettings record {|
    string connectionKey = "PG_Guest";
    string 'table = "cs_mule_framework.cs_async_req_status";
    string description = "reservation-mgr-exp-api";
    int statusUpdateAttempts = 2;
    decimal statusUpdateIntervalSeconds = 5;
|};

# Error-message mapping from the database (Mule `resilience.dbErrorMappingEnabled`).
#
# + enabled - Look up a mapped message for a failed request
# + connectionKey - db-sys-api connection key
# + query - Select on cs_mule_framework.cs_error_mapping (columns endpoint, error, type, code, the
# Mule table). Parameters: `:endpoint` (inbound path), `:code` (status, text), `:type` (error type).
# A row with the exact type wins over a row with a blank type
type ErrorMappingSettings record {|
    boolean enabled = false;
    string connectionKey = "PG_Guest";
    string query = "SELECT endpoint, error, type, code FROM cs_mule_framework.cs_error_mapping "
        + "WHERE endpoint = :endpoint AND code = :code AND (type = :type OR type IS NULL OR type = '')";
|};

configurable string env = ?;
configurable string deploymentTarget = "shore";
configurable int httpPort = 8081;
# Mule listener path `${app.name}/*`.
configurable string basePath = "/reservation-mgr-exp-api";

# reservation-common-proc-api (Mule `reservation.host`, `httpRequest.internal.*`).
configurable commons:DownstreamSettings commonProc = {url: "https://int-api.aroyacruises.com", timeoutSeconds: 45};
configurable string commonProcPaymentPath = "/reservation-common-proc-api/v1/process-payment";
# Time allowed for a write (a GraphQL mutation such as `reservationStore`, and process-payment).
# A write is sent once: when it fails or runs out of time it is not sent again, because the
# first one may still finish downstream.
configurable decimal writeTimeoutSeconds = 65;

# db-sys-api (Mule `dbSystemApi.*`); used for async status and error mapping.
configurable commons:DownstreamSettings dbSysApi = {url: "https://int-api.aroyacruises.com", timeoutSeconds: 5};
configurable string dbSysApiPath = "/db-sys-api/v1/db";

# GraphQL root field -> target API (Mule `operationMapping` and `static.operationMapping`).
# Looked up case-insensitively, `operationMapping` first.
configurable map<string> operationMapping = {};
configurable map<string> staticOperationMapping = {};
# Target API name -> path on reservation-common-proc-api. Only `/reservation-common-api` is
# routed today; any other target answers NOT_IMPLEMENTED, as in Mule.
configurable map<string> routeTargets = {"/reservation-common-api": "/reservation-common-proc-api/v1/integration-tasks"};

configurable commons:CircuitBreakerSettings circuitBreaker = {enabled: false, dependencyName: "reservation-common-proc-api"};
configurable commons:RetryPolicy retryPolicy = {};
# Redis for the circuit-breaker state (intg-redis). Only needed when the breaker is enabled.
configurable commons:RedisSettings breakerRedis = {enabled: false};
configurable commons:AuditSettings audit = {};
# The Mule Kafka producer connections (global-config.xml), one per target. The one used follows
# `env` and `deploymentTarget` as the Mule choice on mule.env / mule.deploymentTarget did.
configurable core:KafkaProducers kafkaProducers = {};
configurable commons:NotifySettings notification = {};
configurable AsyncSettings asyncRequests = {};

# The `flightpromotion` operation (Mule flight-promotions sub-flow), now through seaware-sys-api.
#
# + enabled - Serve the operation. Off until the business confirms it is still needed
# (docs/MIGRATION-FINDINGS.md, open items); while off it answers NOT_IMPLEMENTED as before
# + sysApi - seaware-sys-api
# + path - Its integration-tasks path
# + rootField - Root field that selects the operation (Mule compared it exactly)
type FlightPromotionSettings record {|
    boolean enabled = false;
    commons:DownstreamSettings sysApi = {url: "http://seaware-sys-api.wso2.svc", timeoutSeconds: 45};
    string path = "/seaware-sys-api/v1/integration-tasks";
    string rootField = "flightpromotion";
|};

configurable FlightPromotionSettings flightPromotion = {};
configurable ErrorMappingSettings errorMapping = {};
