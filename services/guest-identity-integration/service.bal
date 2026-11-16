// guest-identity-integration: HTTP wiring and the role switch. Logic lives in worker.bal,
// review.bal, reconcile.bal and modules/core.

import guest_identity_integration.core;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/time;
import ballerinax/kafka as k;
import ballerinax/prometheus as _;

import aroya/integration_commons as commons;

final PythonApi pythonApi = check new HttpPython(python, pythonServiceToken);
final CrmApi crmApi = check new HttpCrm(zohoSysApi, zohoSystemPath);
final EventBus eventBus = role == "smoke" ? new NoBus() : busOf(kafkaConfig);

isolated function liveDeps() returns Deps => {python: pythonApi, crm: crmApi, bus: eventBus};

isolated boolean workerReady = false;

isolated function hasRole(string r) returns boolean => role == r || (role == "all" && r != "reconcile");

isolated function respond(Answer a, string cid) returns http:Response {
    http:Response res = new;
    res.statusCode = a.status;
    res.setJsonPayload(a.body);
    res.setHeader(commons:CORRELATION_HEADER, cid);
    return res;
}

isolated function cidOf(http:Request req) returns string {
    string? x = commons:headerOf(req, "X-Correlation-Id");
    return x is string && x.trim() != "" ? x.trim() : commons:correlationIdOf(req);
}

isolated function reviewerFrom(http:Request req) returns core:Reviewer|error =>
    core:reviewerOf(commons:headerOf(req, "X-Reviewer-Context") ?: "", commons:headerOf(req, "X-Reviewer-Signature") ?: "",
        reviewAuth.signingSecret, time:utcNow()[0], reviewAuth.maxAgeSeconds);

isolated function authProblem(error e, string cid) returns Answer {
    if e.message() == "REVIEW_AUTH_NOT_CONFIGURED" {
        return problem(503, "REVIEW_AUTH_NOT_CONFIGURED", "Reviewer authentication is not set up.", cid);
    }
    return problem(401, "UNAUTHORIZED", "The reviewer context is missing, invalid or expired.", cid);
}

isolated function tokenOk(http:Request req) returns boolean|Answer {
    if webhookToken == "" {
        return problem(503, "WEBHOOK_NOT_CONFIGURED", "The webhook token is not set.", cidOf(req));
    }
    string got = commons:headerOf(req, "X-Webhook-Token") ?: "";
    return got.length() == webhookToken.length() && got == webhookToken;
}

final http:Service reviewService = isolated service object {
    isolated resource function get health/live() returns json => {status: "UP"};

    isolated resource function get health/ready() returns http:Response => readiness();

    # Opens a review case: proxied to Python, zero CRM reads.
    isolated resource function get review\-cases/[string caseId](http:Request req) returns http:Response {
        string cid = cidOf(req);
        core:Reviewer|error reviewer = reviewerFrom(req);
        if reviewer is error {
            return respond(authProblem(reviewer, cid), cid);
        }
        return respond(openCase(liveDeps(), reviewer, caseId, cid), cid);
    }

    # Submits a reviewer decision.
    isolated resource function post review\-cases/[string caseId]/decisions(http:Request req) returns http:Response {
        string cid = cidOf(req);
        core:Reviewer|error reviewer = reviewerFrom(req);
        if reviewer is error {
            return respond(authProblem(reviewer, cid), cid);
        }
        json|error body = req.getJsonPayload();
        if body !is map<json> {
            return respond(problem(400, "INVALID_REQUEST", "The body is not a JSON object.", cid), cid);
        }
        Answer a = submitDecision(liveDeps(), reviewer, caseId, body, cid);
        log:printInfo("Review decision submitted", correlationId = cid, caseId = core:masked(caseId),
                status = a.status);
        return respond(a, cid);
    }

    # CRM workflow webhook (direct create / identity-field edit) and the ingress of
    # guest-identity-proc-api: a full Guest snapshot in, one Kafka event out.
    isolated resource function post crm\-events(http:Request req) returns http:Response {
        string cid = cidOf(req);
        boolean|Answer ok = tokenOk(req);
        if ok is Answer {
            return respond(ok, cid);
        }
        if !ok {
            return respond(problem(401, "UNAUTHORIZED", "The webhook token is wrong.", cid), cid);
        }
        json|error body = req.getJsonPayload();
        return respond(acceptGuestEvent(liveDeps(), body is json ? body : (), cid), cid);
    }
};

isolated function readiness() returns http:Response {
    http:Response res = new;
    boolean ready = true;
    if hasRole("worker") {
        lock {
            ready = workerReady;
        }
    }
    res.statusCode = ready ? 200 : 503;
    res.setJsonPayload({status: ready ? "UP" : "DOWN", role});
    return res;
}

isolated function healthService() returns http:Service => isolated service object {
    isolated resource function get health/live() returns json => {status: "UP"};

    isolated resource function get health/ready() returns http:Response => readiness();
};

function init() returns error? {
    if ["worker", "review", "reconcile", "all", "smoke"].indexOf(role) is () {
        return error("role must be worker, review, reconcile, all or smoke");
    }
    log:printInfo("guest-identity-integration starting", role = role, env = env,
            kafkaSet = kafkaConfig.bootstrapServers.length() > 0);
    if role == "reconcile" || role == "smoke" {
        return; // main() runs once and the process ends: no listener
    }
    http:Listener l = check new (httpPort, host = httpHost, timeout = 30);
    // /health/live and /health/ready for the probes; the same under basePath for the gateway
    check l.attach(healthService(), "/");
    check l.attach(hasRole("review") ? reviewService : healthService(), basePath);
    check l.'start();
    runtime:registerListener(l);
    if hasRole("worker") {
        if kafkaConfig.bootstrapServers.length() == 0 {
            log:printWarn("Worker not started: kafka.bootstrapServers is empty (readiness stays DOWN)");
        } else {
            _ = start consumeForever(liveDeps());
        }
    }
}

public function main() returns error? {
    if role == "smoke" {
        return runKafkaSmoke(kafkaConfig, smokeTestTopic);
    }
    if role != "reconcile" {
        return;
    }
    StateStore st = check stateOf();
    ReconcileReport rep = check runReconcile(liveDeps(), st);
    if rep.failures > 0 {
        return error(string `Reconciliation finished with ${rep.failures} failure(s); the watermark was not advanced`);
    }
}

# The worker's consumer: manual commits after each fully handled batch; a batch whose DLQ write
# failed is not committed, the consumer is re-created and re-reads from the last commit (order kept).
isolated function consumeForever(Deps d) {
    while true {
        k:Consumer|error c = consumerOf(kafkaConfig);
        if c is error {
            log:printError("Kafka consumer could not be created; retrying in 30 s", reason = c.message());
            runtime:sleep(30);
            continue;
        }
        lock {
            workerReady = true;
        }
        boolean healthy = true;
        while healthy {
            k:BytesConsumerRecord[]|k:Error records = c->poll(kafkaConfig.pollSeconds);
            if records is k:Error {
                log:printWarn("Kafka poll failed", reason = records.message());
                healthy = false;
                break;
            }
            foreach k:BytesConsumerRecord rec in records {
                Outcome|error o = handleRaw(d, rec.offset.partition.topic, rec.value);
                if o is error {
                    log:printError("DLQ not reachable: batch not committed, re-reading", reason = o.message());
                    healthy = false;
                    break;
                }
            }
            if healthy && records.length() > 0 {
                k:Error? committed = c->'commit();
                if committed is k:Error {
                    log:printWarn("Offset commit failed; the batch may be delivered again (idempotent)",
                            reason = committed.message());
                }
            }
        }
        lock {
            workerReady = false;
        }
        k:Error? closed = c->close();
        if closed is k:Error {
            log:printWarn("Kafka consumer close failed", reason = closed.message());
        }
        runtime:sleep(5);
    }
}

isolated function consumerOf(KafkaSettings s) returns k:Consumer|error {
    k:ConsumerConfiguration c = {
        groupId: s.consumerGroup,
        topics: [s.evaluationTopic, s.reevaluationTopic],
        offsetReset: k:OFFSET_RESET_EARLIEST,
        autoCommit: false,
        maxPollRecords: s.maxPollRecords,
        maxPollInterval: s.maxPollIntervalMs,
        clientId: s.clientId + "-worker",
        isolationLevel: k:ISOLATION_COMMITTED,
        securityProtocol: check protocolOf(s.securityProtocol)
    };
    k:AuthenticationConfiguration? auth = check authOf(s);
    if auth is k:AuthenticationConfiguration {
        c.auth = auth;
    }
    if s.caCertPath != "" {
        c.secureSocket = {cert: s.caCertPath};
    }
    return new (s.bootstrapServers, c);
}
