// Nightly reconciliation (plan 17): delta from CRM since the watermark, republish PENDING work,
// commit decisions CRM already holds. It never writes an identity to CRM and never changes a
// committed ID: anything that needs a decision goes back through Python via the event topics.

import guest_identity_integration.core;

import ballerina/http;
import ballerina/log;
import ballerina/time;
import ballerinax/redis;

import aroya/integration_commons as commons;

# Where the lock and the watermark are kept.
public type StateStore isolated object {
    isolated function tryLock(string key, int seconds) returns boolean|error;
    isolated function unlock(string key) returns error?;
    isolated function get(string key) returns string?|error;
    isolated function put(string key, string value) returns error?;
};

isolated class RedisState {
    *StateStore;
    private final redis:Client r;

    isolated function init(redis:Client r) {
        self.r = r;
    }

    isolated function tryLock(string key, int seconds) returns boolean|error {
        boolean got = check self.r->setNx(key, core:now());
        if got {
            _ = check self.r->expire(key, seconds);
        }
        return got;
    }

    isolated function unlock(string key) returns error? {
        _ = check self.r->del([key]);
    }

    isolated function get(string key) returns string?|error {
        return self.r->get(key);
    }

    isolated function put(string key, string value) returns error? {
        _ = check self.r->set(key, value);
    }
}

public isolated class MemoryState {
    *StateStore;
    private map<string> values = {};

    isolated function tryLock(string key, int seconds) returns boolean|error {
        lock {
            if self.values.hasKey(key) {
                return false;
            }
            self.values[key] = "locked";
            return true;
        }
    }

    isolated function unlock(string key) returns error? {
        lock {
            _ = self.values.removeIfHasKey(key);
        }
    }

    isolated function get(string key) returns string?|error {
        lock {
            return self.values[key];
        }
    }

    isolated function put(string key, string value) returns error? {
        lock {
            self.values[key] = value;
        }
    }
}

# What one run did (counts only, no personal data).
public type ReconcileReport record {|
    boolean ran = false;
    string skippedReason = "";
    int deltaRecords = 0;
    int reevaluationsPublished = 0;
    int pendingRepublished = 0;
    int commitsRetried = 0;
    int failures = 0;
    boolean watermarkAdvanced = false;
|};

isolated function selectFields() returns string {
    string out = "id";
    foreach string f in core:snapshotFieldsOf(crmFields) {
        out += ", " + f;
    }
    return out + ", " + crmFields.decisionId;
}

isolated function minutesAgo(int minutes) returns string {
    time:Utc t = time:utcAddSeconds(time:utcNow(), -<decimal>(minutes * 60));
    string s = time:utcToString(t);
    int? dot = s.indexOf(".");
    return (dot is int ? s.substring(0, dot) : s.substring(0, s.length() - 1)) + "+00:00";
}

isolated function later(string a, string b) returns boolean {
    time:Utc|error x = time:utcFromString(a);
    time:Utc|error y = time:utcFromString(b);
    return x is time:Utc && y is time:Utc ? time:utcDiffSeconds(x, y) > 0d : a > b;
}

# One reconciliation run.
#
# + d - Dependencies
# + st - Lock and watermark store
# + return - What was done; an error only when the run could not start
public isolated function runReconcile(Deps d, StateStore st) returns ReconcileReport|error {
    string cid = "RECON-" + core:now();
    string lockKey = reconcile.stateKeyPrefix + "lock";
    string wmKey = reconcile.stateKeyPrefix + "watermark";
    if !check st.tryLock(lockKey, reconcile.lockSeconds) {
        log:printWarn("Reconciliation skipped: another run holds the lock", correlationId = cid);
        return {skippedReason: "LOCKED"};
    }
    ReconcileReport rep = {ran: true};
    do {
        string watermark = (check st.get(wmKey)) ?: reconcile.initialWatermark;
        string newest = watermark;
        boolean complete = true;

        // 1-3, 5. Guests changed since the watermark
        int page = 0;
        boolean more = true;
        while more {
            if page >= reconcile.maxPages {
                complete = false;
                break;
            }
            string q = string `select ${selectFields()} from ${crmModules.guests} where (Modified_Time > '${watermark}' and ${crmFields.directScope} = true) order by Modified_Time asc limit ${page * reconcile.pageSize}, ${reconcile.pageSize}`;
            [map<json>[], boolean] [records, hasMore] = check crmQuery(d.crm, q, cid);
            foreach map<json> rec in records {
                rep.deltaRecords += 1;
                string modified = core:text(rec["Modified_Time"]);
                if later(modified, newest) {
                    newest = modified;
                }
                if !reconcileRecord(d, rec, cid, rep) {
                    complete = false;
                }
            }
            more = hasMore;
            page += 1;
        }

        // 4. Guests still PENDING_IDENTITY after the grace period: republish their evaluation
        page = 0;
        more = true;
        string before = minutesAgo(reconcile.pendingAfterMinutes);
        while more {
            if page >= reconcile.maxPages {
                complete = false;
                break;
            }
            string q = string `select ${selectFields()} from ${crmModules.guests} where (${crmFields.identityStatus} = '${core:PENDING_IDENTITY}' and Modified_Time < '${before}') order by Modified_Time asc limit ${page * reconcile.pageSize}, ${reconcile.pageSize}`;
            [map<json>[], boolean] [records, hasMore] = check crmQuery(d.crm, q, cid);
            foreach map<json> rec in records {
                map<json> event = core:snapshotEventOf(rec, core:EVALUATION, core:CRM_DIRECT, cid, crmFields);
                error? sent = d.bus.publish(kafkaConfig.evaluationTopic, core:text(rec["id"]), event);
                if sent is error {
                    rep.failures += 1;
                    complete = false;
                } else {
                    rep.pendingRepublished += 1;
                }
            }
            more = hasMore;
            page += 1;
        }

        // 8. the watermark moves only when every page and record succeeded
        if complete && newest != watermark {
            check st.put(wmKey, newest);
            rep.watermarkAdvanced = true;
        }
    } on fail error e {
        rep.failures += 1;
        log:printError("Reconciliation stopped; the watermark was not advanced", correlationId = cid,
                reason = e.message());
    }
    error? released = st.unlock(lockKey);
    if released is error {
        log:printWarn("Reconciliation lock not released; it expires by itself", correlationId = cid);
    }
    log:printInfo("Reconciliation finished", correlationId = cid, deltaRecords = rep.deltaRecords,
            reevaluationsPublished = rep.reevaluationsPublished, pendingRepublished = rep.pendingRepublished,
            commitsRetried = rep.commitsRetried, failures = rep.failures, watermarkAdvanced = rep.watermarkAdvanced);
    return rep;
}

# One changed Guest: commit a decision CRM already holds (step 5), and send the snapshot to Python
# so it refreshes the Guest's matching keys (step 3). Returns false on a failure.
isolated function reconcileRecord(Deps d, map<json> rec, string cid, ReconcileReport rep) returns boolean {
    string status = core:text(rec[crmFields.identityStatus]);
    if status == core:PENDING_IDENTITY {
        return true; // handled by the pending pass
    }
    boolean ok = true;
    string decisionId = core:text(rec[crmFields.decisionId]);
    if decisionId.startsWith("IDDEC-") {
        Reply|error r = d.python.call(http:GET, "/v1/guest-identities/decisions/" + decisionId, (), cid);
        if r is error || r.status >= 500 {
            ok = false;
        } else if r.status < 300 {
            string state = core:text(core:pick(r.body, "processingState"));
            if state == "DECIDED_PENDING_CRM" || state == "CRM_UPDATE_FAILED" {
                // CRM shows this decision, so its CRM update succeeded; only the commit is missing
                json link = rec[crmFields.guestIdentity];
                string identityId = core:text(link is map<json> ? link["id"] : link);
                Outcome o = commitInPython(d, decisionId, identityId, core:text(rec["Modified_Time"]), cid);
                if o.result == "DONE" {
                    rep.commitsRetried += 1;
                } else {
                    ok = false;
                }
            }
        }
    }
    if core:text(rec[crmFields.guestIdentity]) != "" || rec[crmFields.guestIdentity] is map<json> {
        map<json> event = core:snapshotEventOf(rec, core:REEVALUATION, core:CRM_DIRECT, cid, crmFields);
        error? sent = d.bus.publish(kafkaConfig.reevaluationTopic, core:text(rec["id"]), event);
        if sent is error {
            ok = false;
        } else {
            rep.reevaluationsPublished += 1;
        }
    }
    if !ok {
        rep.failures += 1;
    }
    return ok;
}

# The state store of the settings.
isolated function stateOf() returns StateStore|error {
    redis:Client|redis:Error? r = commons:newRedisClient(stateRedis, "guest-identity-reconcile");
    if r is redis:Client {
        return new RedisState(r);
    }
    if r is redis:Error {
        return error("Redis for the reconciliation lock could not be reached: " + r.message());
    }
    if !allowMemoryState {
        return error("stateRedis is switched off: the single-run lock and the watermark need Redis "
            + "(allowMemoryState = true only for tests)");
    }
    return new MemoryState();
}
