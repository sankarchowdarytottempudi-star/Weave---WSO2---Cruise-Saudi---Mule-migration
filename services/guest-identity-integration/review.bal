// The Review API orchestration (plan 10.4, 14.4). Opening a case reads only Python (zero CRM
// calls); submitting reads CRM exactly once, then applies Python's crmPatch or reports
// REVIEW_DATA_CHANGED.

import guest_identity_integration.core;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;

# An answer of the Review API.
#
# + status - HTTP status
# + body - Body
public type Answer record {|
    int status;
    json body;
|};

isolated function problem(int status, string code, string message, string cid, map<json> extra = {}) returns Answer {
    map<json> b = {code, message, correlationId: cid};
    foreach [string, json] [k, v] in extra.entries() {
        b[k] = v;
    }
    return {status, body: b};
}

isolated function reviewerHeaders(core:Reviewer reviewer) returns map<string> {
    string roles = "";
    foreach string r in reviewer.roles {
        roles += (roles == "" ? "" : ",") + r;
    }
    return {"X-Reviewer-Id": reviewer.userId, "X-Reviewer-Roles": roles};
}

isolated function passThrough(Reply|error r, string cid) returns Answer {
    if r is error {
        return problem(503, "DECISION_SERVICE_UNAVAILABLE", "The identity decision service could not be reached.", cid);
    }
    return {status: r.status, body: r.body};
}

# GET a review case: Python only, never CRM.
public isolated function openCase(Deps d, core:Reviewer reviewer, string caseId, string cid) returns Answer {
    if !core:mayView(reviewer) {
        return problem(403, "FORBIDDEN", "This user has no identity review role.", cid);
    }
    return passThrough(d.python.call(http:GET, "/v1/review-cases/" + caseId, (), cid, reviewerHeaders(reviewer)), cid);
}

# Submit a reviewer decision (plan 10.4 steps 1-8).
#
# + d - Dependencies
# + reviewer - Authenticated reviewer
# + caseId - Case id
# + input - Workbench body {action, selectedIdentityId?, comment?, versionsShown, idempotencyKey, followUpDate?}
# + cid - Correlation id
# + return - The answer for the Workbench
public isolated function submitDecision(Deps d, core:Reviewer reviewer, string caseId, map<json> input, string cid)
        returns Answer {
    string action = core:text(input["action"]);
    if action == "" || core:text(input["idempotencyKey"]) == "" || input["versionsShown"] !is json[] {
        return problem(400, "INVALID_REQUEST", "action, idempotencyKey and versionsShown are required.", cid);
    }
    if !core:mayDecide(reviewer, action) {
        return problem(403, "FORBIDDEN", "This user may not take this action.", cid);
    }
    map<string> rh = reviewerHeaders(reviewer);
    // 2. Python validates the versions shown and prepares the decision
    map<json> prepRequest = {
        caseId,
        reviewerId: reviewer.userId,
        action,
        selectedIdentityId: input["selectedIdentityId"],
        comment: input["comment"] is string ? core:withoutPersonalDetails(<string>input["comment"]) : (),
        versionsShown: input["versionsShown"],
        idempotencyKey: input["idempotencyKey"],
        followUpDate: input["followUpDate"]
    };
    Reply|error prep = d.python.call(http:POST, "/v1/review-cases/" + caseId + "/decision-preparations",
            prepRequest, cid, rh);
    if prep is error || prep.status >= 300 || prep.body !is map<json> {
        return passThrough(prep, cid);
    }
    map<json> prepared = <map<json>>prep.body;
    string rdId = core:text(prepared["reviewDecisionId"]);
    if core:text(prepared["state"]) == "REVIEW_COMMITTED" {
        return {status: 200, body: {reviewDecisionId: rdId, caseId, state: "REVIEW_COMMITTED", correlationId: cid}};
    }
    json toCheck = prepared["crmRecordsToCheck"];
    string[] ids = [];
    if toCheck is json[] {
        foreach json c in toCheck {
            string id = core:text(core:pick(c, "crmGuestRecordId"));
            if id != "" {
                ids.push(id);
            }
        }
    }
    if rdId == "" || ids.length() == 0 {
        return problem(502, "INVALID_PREPARED_DECISION", "The prepared decision names no CRM records.", cid);
    }
    // 3. ONE batched CRM read of the records Python named
    map<json>[]|CrmError current = crmReadByIds(d.crm, crmModules.guests, ids, core:snapshotFieldsOf(crmFields), cid);
    if current is CrmError {
        _ = reviewFail(d, rdId, true, "CRM_READ_FAILED", cid, rh);
        return problem(503, "REVIEW_CRM_UPDATE_PENDING", "CRM could not be read; nothing was changed. Submit again.",
                cid, {reviewDecisionId: rdId});
    }
    // 4-5. compare; any difference = freshness failure, CRM is not touched
    core:FreshnessProblem[] problems = core:freshnessProblemsOf(toCheck, current, crmFields);
    if problems.length() > 0 {
        json[] snapshots = from map<json> rec in current
            select core:snapshotEventOf(rec, core:REEVALUATION, core:CRM_DIRECT, cid, crmFields);
        json[] changed = from core:FreshnessProblem p in problems
            select p.crmGuestRecordId;
        if snapshots.length() > 0 {
            Reply|error ff = d.python.call(http:POST, "/v1/review-decisions/" + rdId + "/freshness-failed",
                    {snapshots, correlationId: cid}, cid, rh);
            if ff is error || ff.status >= 300 {
                log:printWarn("Python did not take the freshness failure", correlationId = cid, reviewDecisionId = rdId);
            }
        } else {
            _ = reviewFail(d, rdId, false, "REVIEW_RECORDS_MISSING", cid, rh);
        }
        return problem(409, "REVIEW_DATA_CHANGED", "A Guest changed after the case was displayed; refresh it.", cid,
                {caseId, reviewDecisionId: rdId, changedRecords: changed, reasonCodes: ["REVIEW_VERSION_CHANGED"]});
    }
    // 6. apply the exact crmPatch in the controlled order
    core:CrmWrite[]|error writes = core:reviewWritesOf(prepared["crmPatch"], ids[0], caseId, reviewer.userId, rdId,
            crmFields, crmModules);
    if writes is error {
        _ = reviewFail(d, rdId, false, "INVALID_CRM_PATCH", cid, rh);
        return problem(502, "INVALID_CRM_PATCH", writes.message(), cid, {reviewDecisionId: rdId});
    }
    json[] modifiedTimes = [];
    foreach core:CrmWrite w in writes {
        string|CrmError written = crmApply(d.crm, w, cid);
        if written is CrmError {
            _ = reviewFail(d, rdId, true, "CRM_UPDATE_FAILED", cid, rh);
            log:printWarn("Review decision CRM update failed: submit again to retry the same decision",
                    correlationId = cid, reviewDecisionId = rdId, status = written.detail().status);
            return problem(502, "REVIEW_CRM_UPDATE_PENDING", "CRM could not be updated; submit again to retry.", cid,
                    {reviewDecisionId: rdId});
        }
        if w.module == crmModules.guests && written != "" {
            modifiedTimes.push({crmGuestRecordId: w.id, crmModifiedTime: written});
        }
    }
    // 7-8. commit with the same decision id
    foreach int attempt in 1 ... retries.maxAttempts {
        Reply|error c = d.python.call(http:POST, "/v1/review-decisions/" + rdId + "/commit",
                {crmModifiedTimes: modifiedTimes, correlationId: cid}, cid, rh);
        if c is Reply && c.status < 300 {
            return {status: 200, body: {reviewDecisionId: rdId, caseId, state: "REVIEW_COMMITTED", correlationId: cid}};
        }
        if c is Reply && c.status >= 400 && c.status < 500 && c.status != 429 {
            return {status: c.status, body: c.body};
        }
        if attempt < retries.maxAttempts {
            runtime:sleep(backoffOf(attempt));
        }
    }
    return {
        status: 202,
        body: {
            reviewDecisionId: rdId,
            caseId,
            state: "REVIEW_CRM_UPDATE_PENDING",
            message: "CRM is updated; the decision commit is pending and is retried when submitted again.",
            correlationId: cid
        }
    };
}

isolated function reviewFail(Deps d, string rdId, boolean retryable, string code, string cid, map<string> rh)
        returns boolean {
    Reply|error r = d.python.call(http:POST, "/v1/review-decisions/" + rdId + "/fail",
            {retryable, errorCode: code}, cid, rh);
    return r is Reply && r.status < 300;
}

# The CRM workflow webhook / ingress: a full Guest snapshot in, one event out (plan 14.2, 14.3).
#
# + d - Dependencies
# + body - {eventType: "created"|"updated", record: {...CRM Guest...}} or a ready event (schema 1.0)
# + cid - Correlation id
# + return - The answer
public isolated function acceptGuestEvent(Deps d, json body, string cid) returns Answer {
    if body !is map<json> {
        return problem(400, "INVALID_REQUEST", "The body is not a JSON object.", cid);
    }
    map<json> event;
    if core:text(body["schemaVersion"]) != "" {
        event = body; // a ready snapshot event from the ingress (guest-identity-proc-api)
        if core:text(event["correlationId"]) == "" {
            event["correlationId"] = cid;
        }
    } else {
        json rec = body["record"];
        if rec !is map<json> {
            return problem(400, "INVALID_REQUEST", "record is required.", cid);
        }
        string kind = core:text(body["eventType"]).toLowerAscii();
        string eventType = kind == "updated" ? core:REEVALUATION : core:EVALUATION;
        event = core:snapshotEventOf(rec, eventType, core:CRM_DIRECT, cid, crmFields);
    }
    foreach string k in REQUIRED {
        if core:text(event[k]).trim() == "" {
            return problem(400, "INVALID_REQUEST", "The snapshot has no " + k + ".", cid);
        }
    }
    string topic = core:text(event["eventType"]) == core:REEVALUATION ? kafkaConfig.reevaluationTopic : kafkaConfig.evaluationTopic;
    error? sent = d.bus.publish(topic, core:text(event["crmGuestRecordId"]), event);
    if sent is error {
        log:printWarn("Guest event not published: the reconciliation republishes PENDING work", correlationId = cid,
                reason = sent.message());
        return problem(503, "EVENT_NOT_PUBLISHED", "The event could not be published; it is picked up again later.",
                cid);
    }
    return {status: 202, body: {eventId: event["eventId"], eventType: event["eventType"], correlationId: cid}};
}

// Workbench queue, history, assignment and comments (Factory BFF contract). The data lives in the
// Python service (PostgreSQL); these are proxies with the role checks done here as well. None of
// them calls CRM.

const string[] QUEUE_FILTERS = ["kind", "status", "assignee", "page", "pageSize", "limit", "offset", "cursor"];

# GET the review queue: only the known filters are passed on.
public isolated function listCases(Deps d, core:Reviewer reviewer, map<string> filters, string cid) returns Answer {
    if !core:mayView(reviewer) {
        return problem(403, "FORBIDDEN", "This user has no identity review role.", cid);
    }
    map<string> q = {};
    foreach string k in QUEUE_FILTERS {
        string? v = filters[k];
        if v is string && v.trim() != "" && v.length() <= 80 {
            q[k] = v.trim();
        }
    }
    return passThrough(d.python.call(http:GET, "/v1/review-cases" + queryOf(q), (), cid, reviewerHeaders(reviewer)), cid);
}

# GET a case's history.
public isolated function caseHistory(Deps d, core:Reviewer reviewer, string caseId, string cid) returns Answer {
    if !core:mayView(reviewer) {
        return problem(403, "FORBIDDEN", "This user has no identity review role.", cid);
    }
    return passThrough(d.python.call(http:GET, "/v1/review-cases/" + caseId + "/history", (), cid,
            reviewerHeaders(reviewer)), cid);
}

# Take a case, or (supervisor) hand it to someone. assignedBy is always the signed-in reviewer.
public isolated function assignCase(Deps d, core:Reviewer reviewer, string caseId, json input, string cid) returns Answer {
    string assignee = core:text(core:pick(input, "assigneeId")).trim();
    if assignee == "" || assignee.length() > 80 {
        return problem(400, "INVALID_REQUEST", "assigneeId is required.", cid);
    }
    if !core:mayAssign(reviewer, assignee) {
        return problem(403, "FORBIDDEN", "Only a supervisor can give a case to someone else.", cid);
    }
    return passThrough(d.python.call(http:POST, "/v1/review-cases/" + caseId + "/assignment",
            {assigneeId: assignee, assignedBy: reviewer.userId}, cid, reviewerHeaders(reviewer)), cid);
}

# Comment on a case. authorId is always the signed-in reviewer; e-mail addresses and long numbers
# are removed from the text first (history reaches audit users unmasked).
public isolated function commentCase(Deps d, core:Reviewer reviewer, string caseId, json input, string cid) returns Answer {
    if !core:mayComment(reviewer) {
        return problem(403, "FORBIDDEN", "Your role can read cases but not comment.", cid);
    }
    string comment = core:text(core:pick(input, "text")).trim();
    if comment == "" || comment.length() > 2000 {
        return problem(400, "INVALID_REQUEST", "Write a comment of up to 2000 characters.", cid);
    }
    return passThrough(d.python.call(http:POST, "/v1/review-cases/" + caseId + "/comments",
            {authorId: reviewer.userId, text: core:withoutPersonalDetails(comment)}, cid,
            reviewerHeaders(reviewer)), cid);
}
