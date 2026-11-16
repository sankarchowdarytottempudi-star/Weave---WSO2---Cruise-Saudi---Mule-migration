import ballerina/http;
import ballerina/log;
import ballerinax/prometheus as _;

// payment-reconciliation-proc-api on WSO2 (Ballerina).
//
// The old application had no addresses of its own: it is one job that runs on a timer (job.bal).
// This service therefore serves the health checks only.
//
// The timer hands payments to process-payment, so it has a switch ([...scheduler] enabled) that
// is off by default. With the switch off no client is created and nothing is called. With the
// switch on and a needed setting missing, the job is not started and the start-up line says
// which setting; the service itself keeps running.

listener http:Listener httpListener = new (httpPort);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    log:printInfo("payment-reconciliation-proc-api starting", env = env, basePath = basePath, timer = startTimer(),
            summaryEmail = email.enabled ? "on" : "off");
}

// Nothing is served under the base path.
final http:Service apiService = service object {
};

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}
