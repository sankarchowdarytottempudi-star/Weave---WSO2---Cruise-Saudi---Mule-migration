// The identity worker (plan 14.1 steps 5-9, 14.5): one evaluation or re-evaluation event at a time,
// Python decides, this applies the decision to CRM, then commits it in Python.

import guest_identity_integration.core;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;

# What became of one event.
#
# + result - DONE | RETRY (try again later) | DLQ (do not try again)
# + stage - Where it stopped (VALIDATION, PYTHON_EVALUATE, CRM_UPDATE, PYTHON_COMMIT, ...)
# + errorCode - Why
# + httpStatus - HTTP status of the failing call
# + decisionId - Python decision id, when there was one
public type Outcome record {|
    string result;
    string stage = "";
    string errorCode = "";
    int? httpStatus = ();
    string decisionId = "";
|};

# The dependencies of the worker (real clients in the service, stand-ins in tests).
public type Deps record {|
    PythonApi python;
    CrmApi crm;
    EventBus bus;
|};

const string[] REQUIRED = [
    "schemaVersion",
    "eventId",
    "eventType",
    "correlationId",
    "sourceSystem",
    "sourceRecordId",
    "crmGuestRecordId",
    "crmModifiedTime"
];

isolated function done(string stage = "", string code = "", string decisionId = "") returns Outcome =>
    {result: "DONE", stage, errorCode: code, decisionId};

isolated function retryLater(string stage, string code, int? status = (), string decisionId = "") returns Outcome =>
    {result: "RETRY", stage, errorCode: code, httpStatus: status, decisionId};

isolated function dlq(string stage, string code, int? status = (), string decisionId = "") returns Outcome =>
    {result: "DLQ", stage, errorCode: code, httpStatus: status, decisionId};

# Python's error code from an error reply.
isolated function codeOf(Reply r) returns string {
    string c = core:text(core:pick(r.body, "code"));
    if c == "" {
        c = core:text(core:pick(r.body, "detail", "code"));
    }
    return c;
}

# Processes one event once. Never throws; the caller decides about retries and the DLQ.
#
# + d - Dependencies
# + topic - Topic it came from
# + event - The event
# + return - The outcome
public isolated function processEvent(Deps d, string topic, map<json> event) returns Outcome {
    foreach string k in REQUIRED {
        if core:text(event[k]).trim() == "" {
            return dlq("VALIDATION", "INVALID_EVENT");
        }
    }
    string cid = core:text(event["correlationId"]);
    string guestId = core:text(event["crmGuestRecordId"]);
    boolean reeval = topic == kafkaConfig.reevaluationTopic || core:text(event["eventType"]) == core:REEVALUATION;
    string path = reeval ? "/v1/guest-identities/re-evaluate" : "/v1/guest-identities/evaluate";

    Reply|error r = d.python.call(http:POST, path, event, cid);
    if r is error {
        return retryLater("PYTHON_EVALUATE", "PYTHON_UNREACHABLE");
    }
    if r.status == 409 && codeOf(r) == "STALE_CRM_EVENT" {
        log:printInfo("Older event than CRM's version: rejected by Python, nothing applied", correlationId = cid,
                guest = core:masked(guestId));
        return done("PYTHON_EVALUATE", "STALE_CRM_EVENT");
    }
    if r.status >= 500 || r.status == 429 {
        return retryLater("PYTHON_EVALUATE", codeOf(r) == "" ? "PYTHON_UNAVAILABLE" : codeOf(r), r.status);
    }
    if r.status >= 400 || r.body !is map<json> {
        return dlq("PYTHON_EVALUATE", codeOf(r) == "" ? "PYTHON_REJECTED" : codeOf(r), r.status);
    }
    map<json> decision = <map<json>>r.body;
    return applyDecision(d, event, decision, cid);
}

# Applies a decision to CRM and commits it (also used by the reconciliation for pending decisions).
isolated function applyDecision(Deps d, map<json> event, map<json> decision, string cid) returns Outcome {
    string decisionId = core:text(decision["decisionId"]);
    string guestId = core:text(event["crmGuestRecordId"]);
    string state = core:text(decision["processingState"]);
    if state == "COMMITTED" || decision["crmUpdateRequired"] == false {
        // duplicate event, excluded guest, or nothing for CRM: Python already holds the final state
        log:printInfo("Decision needs no CRM update", correlationId = cid, decisionId = decisionId, state = state);
        return done("PYTHON_EVALUATE", "", decisionId);
    }
    if state == "FAILED" || state == "REJECTED_STALE" {
        return dlq("PYTHON_EVALUATE", "DECISION_" + state, (), decisionId);
    }
    if decisionId == "" {
        return dlq("PYTHON_EVALUATE", "DECISION_WITHOUT_ID");
    }
    // Committed IDs never change here (plan 17): a pair different from the Guest's current one is refused.
    string currentGlobal = core:text(event["currentGlobalId"]);
    string newGlobal = core:text(decision["globalId"]);
    if currentGlobal != "" && newGlobal != "" && currentGlobal != newGlobal {
        _ = failInPython(d, decisionId, false, "ID_CHANGE_REFUSED", cid);
        return dlq("CRM_UPDATE", "ID_CHANGE_REFUSED", (), decisionId);
    }

    string identityRecordId = core:text(decision["crmIdentityRecordId"]);
    string guestModified = "";
    do {
        map<json>? identity = core:identityRecordOf(decision);
        if identity is map<json> {
            identityRecordId = check crmUpsert(d.crm, crmModules.identities, "Global_ID", identity, cid);
        }
        guestModified = check crmUpdate(d.crm, crmModules.guests, guestId,
                core:contactPatchOf(decision, identityRecordId, cid, crmFields), cid);
        map<json>? reviewCase = core:reviewCaseRecordOf(decision, guestId, identityRecordId);
        if reviewCase is map<json> {
            _ = check crmUpsert(d.crm, crmModules.reviewCases, "Case_ID", reviewCase, cid);
        }
    } on fail error e {
        int? status = e is CrmError ? e.detail().status : ();
        log:printWarn("CRM update failed: the same decision is retried", correlationId = cid, decisionId = decisionId,
                guest = core:masked(guestId), status = status);
        _ = failInPython(d, decisionId, true, "CRM_UPDATE_FAILED", cid);
        return retryLater("CRM_UPDATE", "CRM_UPDATE_FAILED", status, decisionId);
    }
    return commitInPython(d, decisionId, identityRecordId, guestModified, cid);
}

isolated function failInPython(Deps d, string decisionId, boolean retryable, string code, string cid) returns boolean {
    Reply|error r = d.python.call(http:POST, "/v1/guest-identities/decisions/" + decisionId + "/fail",
            {retryable, errorCode: code, correlationId: cid}, cid);
    return r is Reply && r.status < 300;
}

# Commits in Python; a failing commit is repeated on its own (the CRM writes are not redone).
isolated function commitInPython(Deps d, string decisionId, string identityRecordId, string guestModified,
        string cid) returns Outcome {
    json body = {
        crmIdentityRecordId: identityRecordId == "" ? () : identityRecordId,
        crmGuestModifiedTime: guestModified == "" ? () : guestModified,
        correlationId: cid
    };
    int status = 0;
    foreach int attempt in 1 ... retries.maxAttempts {
        Reply|error r = d.python.call(http:POST, "/v1/guest-identities/decisions/" + decisionId + "/commit", body, cid);
        if r is Reply && r.status < 300 {
            log:printInfo("Decision applied to CRM and committed", correlationId = cid, decisionId = decisionId);
            return done("PYTHON_COMMIT", "", decisionId);
        }
        if r is Reply && r.status >= 400 && r.status < 500 && r.status != 429 {
            return dlq("PYTHON_COMMIT", codeOf(r) == "" ? "COMMIT_REJECTED" : codeOf(r), r.status, decisionId);
        }
        status = r is Reply ? r.status : 0;
        if attempt < retries.maxAttempts {
            runtime:sleep(backoffOf(attempt));
        }
    }
    // CRM already holds the decision; the event is retried (Python returns the same decision, the CRM
    // writes repeat with the same values) and the reconciliation commits it if retries run out.
    return retryLater("PYTHON_COMMIT", "COMMIT_FAILED", status == 0 ? () : status, decisionId);
}

# Wait before attempt n+1: first, doubled each time, capped.
public isolated function backoffOf(int attempt) returns decimal {
    decimal pause = retries.firstBackoffSeconds;
    foreach int _ in 1 ..< attempt {
        pause = pause * 2;
        if pause >= retries.maxBackoffSeconds {
            return retries.maxBackoffSeconds;
        }
    }
    return pause < retries.maxBackoffSeconds ? pause : retries.maxBackoffSeconds;
}

# Processes one event with bounded retries; what still fails goes to the DLQ. Returns only when
# the event is finished (done or dead-lettered), so the offset may then be committed.
#
# + d - Dependencies
# + topic - Topic
# + event - Event
# + return - The final outcome, or an error when even the DLQ could not be written (offset not committed)
public isolated function handleEvent(Deps d, string topic, map<json> event) returns Outcome|error {
    string first = core:now();
    Outcome o = {result: "RETRY"};
    int attempts = 0;
    while attempts < retries.maxAttempts {
        attempts += 1;
        o = processEvent(d, topic, event);
        if o.result != "RETRY" {
            break;
        }
        if attempts < retries.maxAttempts {
            log:printWarn("Event failed, retrying", correlationId = core:text(event["correlationId"]),
                    stage = o.stage, errorCode = o.errorCode, attempt = attempts);
            runtime:sleep(backoffOf(attempts));
        }
    }
    if o.result == "DONE" {
        return o;
    }
    map<json> dead = core:dlqEventOf(event, topic, o.stage, o.errorCode, o.httpStatus, o.result == "RETRY",
            attempts, first, o.decisionId);
    log:printError("Event sent to the DLQ", correlationId = core:text(event["correlationId"]), stage = o.stage,
            errorCode = o.errorCode, attempts = attempts, guest = core:masked(core:text(event["crmGuestRecordId"])));
    check d.bus.publish(kafkaConfig.dlqTopic, core:text(event["crmGuestRecordId"]), dead);
    return o;
}

# A record that is not a JSON object goes straight to the DLQ with its hash only.
public isolated function handleRaw(Deps d, string topic, byte[] value) returns Outcome|error {
    string|error s = string:fromBytes(value);
    json|error parsed = s is string ? s.fromJsonString() : s;
    if parsed is map<json> {
        return handleEvent(d, topic, parsed);
    }
    map<json> dead = core:dlqEventOf({"payload": s is string ? s : ""}, topic, "VALIDATION", "NOT_JSON", (), false, 1,
                                     core:now(), "");
    check d.bus.publish(kafkaConfig.dlqTopic, "unparsable", dead);
    return dlq("VALIDATION", "NOT_JSON");
}
