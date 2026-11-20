import reservation_mgr_exp_api.core;
import ballerina/http;
import ballerina/log;
import ballerinax/jaeger as _;
import ballerinax/prometheus as _;

// reservation-mgr-exp-api on WSO2 (Ballerina). Replaces the Mule project of the same name.
//
// Resources (unchanged for callers, Mule RAML 1.0.6):
//   POST {basePath}/v1/integration-tasks   GraphQL document; routed on its root field
//   POST {basePath}/v2/integration-tasks   same, client_version v2
//   POST {basePath}/v1/process-payment     passed to reservation-common-proc-api
//   GET  {basePath}/asyncstatus?uuid=...   status of an async request
// Header client_asyncFlag: true on integration-tasks answers 202 {"UUID": ...} at once and
// processes the request in the background; the outcome is stored through db-sys-api.

listener http:Listener httpListener = new (httpPort);

function init() returns error? {
    check httpListener.attach(expService, basePath);
    log:printInfo("reservation-mgr-exp-api starting", env = env, deploymentTarget = deploymentTarget,
            basePath = basePath, commonProc = commonProc.url, circuitBreaker = circuitBreaker.enabled,
            mappedOperations = operations.length() + staticOperations.length(),
            availabilityCache = availabilityCache.describe());
    // which Mule producer connection is used and whether records are on; never its address
    log:printInfo("Kafka records", state = audit.auditEnabled || audit.errorEnabled ? "on" : "off",
            producer = kafkaProducer, muleEnv = env, deploymentTarget = deploymentTarget,
            brokersSet = core:recordSettingsOf(audit, kafkaProducers, kafkaProducer).bootstrapServers.length() > 0);
}

final http:Service expService = isolated service object {

    isolated resource function post v1/integration\-tasks(http:Caller caller, http:Request request) returns http:Response {
        return handleIntegrationTask(caller, request, "v1");
    }

    isolated resource function post v2/integration\-tasks(http:Caller caller, http:Request request) returns http:Response {
        return handleIntegrationTask(caller, request, "v2");
    }

    isolated resource function post v1/process\-payment(http:Request request) returns http:Response {
        return handlePayment(request);
    }

    isolated resource function get asyncstatus(http:Request request, string? uuid) returns http:Response {
        return handleAsyncStatus(request, uuid);
    }
};

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}
