// In-memory stand-ins of Python, the CRM (zoho-sys-api) and Kafka, with call counters.

import guest_identity_integration.core;

import ballerina/http;

# Behaves like the Python decision API for the paths the integration uses.
isolated class MemPython {
    *PythonApi;
    private string[] calls = [];
    private map<json> byKey = {};
    private map<string> stateOf = {};
    private map<string> lastModified = {};
    private int pairs = 0;
    private int commitFailures = 0;
    private int evaluateFailures = 0;
    private boolean unreachable = false;
    private string[] prepRecords = ["G1", "G2"];
    private string[] prepTimes = ["2026-11-16T10:00:00+00:00", "2026-11-16T09:40:00+00:00"];
    private map<json> crmPatch = {
        "identityStatus": "CONFIRMED_SAME_PERSON",
        "reviewCaseId": "RC-1",
        "reviewAction": "CONFIRM_SAME_PERSON",
        "guestIdentityId": "I200",
        "aliasIdentityId": "I100"
    };

    isolated function setCommitFailures(int n) {
        lock {
            self.commitFailures = n;
        }
    }

    isolated function setEvaluateFailures(int n) {
        lock {
            self.evaluateFailures = n;
        }
    }

    isolated function setUnreachable(boolean b) {
        lock {
            self.unreachable = b;
        }
    }

    isolated function setPatch(map<json> p0) {
        map<json> & readonly p = p0.cloneReadOnly();
        lock {
            self.crmPatch = p.clone();
        }
    }

    isolated function pairsReserved() returns int {
        lock {
            return self.pairs;
        }
    }

    isolated function count(string prefix) returns int {
        lock {
            int n = 0;
            foreach string c in self.calls {
                if c.startsWith(prefix) {
                    n += 1;
                }
            }
            return n;
        }
    }

    isolated function state(string decisionId) returns string {
        lock {
            return self.stateOf[decisionId] ?: "";
        }
    }

    isolated function call(string method, string path, json body0, string correlationId,
            map<string> headers0 = {}) returns Reply|error {
        json & readonly body = body0.cloneReadOnly();
        map<string> & readonly headers = headers0.cloneReadOnly();
        lock {
            self.calls.push(method + " " + path);
            if self.unreachable {
                return error("connection refused");
            }
            if path.endsWith("/evaluate") || path.endsWith("/re-evaluate") {
                if self.evaluateFailures > 0 {
                    self.evaluateFailures -= 1;
                    return {status: 503, body: {code: "INTERNAL_ERROR", message: "db down"}};
                }
                string key = core:text(core:pick(body, "idempotencyKey"));
                string guest = core:text(core:pick(body, "crmGuestRecordId"));
                string modified = core:text(core:pick(body, "crmModifiedTime"));
                json? seen = self.byKey[key];
                if seen is map<json> {
                    map<json> d = seen.clone();
                    d["processingState"] = self.stateOf[core:text(d["decisionId"])] ?: "";
                    return {status: 200, body: d.clone()};
                }
                string? last = self.lastModified[guest];
                if last is string && last > modified {
                    return {status: 409, body: {code: "STALE_CRM_EVENT", message: "older"}};
                }
                self.lastModified[guest] = modified;
                string current = core:text(core:pick(body, "currentGlobalId"));
                map<json> d;
                string id = "IDDEC-" + (self.byKey.length() + 1).toString();
                if current != "" {
                    d = {
                        decisionId: id,
                        decision: "KEEP_EXISTING_IDENTITY",
                        decisionType: "NONE",
                        identityStatus: "IDENTITY_REUSED_CERTAIN",
                        reviewRequired: false,
                        ruleVersion: "1.0",
                        reasonCodes: [],
                        crmUpdateRequired: false,
                        processingState: "COMMITTED"
                    };
                    self.stateOf[id] = "COMMITTED";
                } else {
                    self.pairs += 1;
                    string n = self.pairs.toString();
                    d = {
                        decisionId: id,
                        decision: "CREATE_NEW_IDENTITY",
                        decisionType: "NEW",
                        identityStatus: "NEW_IDENTITY_CREATED",
                        globalId: "01JTESTGLOBAL000000000000" + n,
                        loyaltyId: "120000000" + n,
                        provisional: false,
                        reviewRequired: false,
                        ruleVersion: "1.0",
                        reasonCodes: ["NO_CANDIDATE"],
                        crmUpdateRequired: true,
                        processingState: "DECIDED_PENDING_CRM"
                    };
                    self.stateOf[id] = "DECIDED_PENDING_CRM";
                }
                self.byKey[key] = d.clone();
                return {status: 200, body: d.clone()};
            }
            if path.startsWith("/v1/guest-identities/decisions/") {
                string id = re `/`.split(path)[4];
                if path.endsWith("/commit") {
                    if self.commitFailures > 0 {
                        self.commitFailures -= 1;
                        return {status: 503, body: {code: "INTERNAL_ERROR"}};
                    }
                    self.stateOf[id] = "COMMITTED";
                    return {status: 200, body: {decisionId: id, processingState: "COMMITTED"}};
                }
                if path.endsWith("/fail") {
                    self.stateOf[id] = core:pick(body, "retryable") == true ? "CRM_UPDATE_FAILED" : "FAILED";
                    return {status: 200, body: {decisionId: id}};
                }
                string? st = self.stateOf[id];
                if st is () {
                    return {status: 404, body: {code: "NOT_FOUND"}};
                }
                return {status: 200, body: {decisionId: id, processingState: st}};
            }
            if method == http:GET && path.startsWith("/v1/review-cases/") {
                return {
                    status: 200,
                    body: {
                        caseId: "RC-1",
                        caseStatus: "REVIEW_OPEN",
                        kind: "FOUR_FIELD_REVIEW",
                        priority: "NORMAL",
                        ruleVersion: "1.0",
                        reasonCodes: [],
                        candidates: [],
                        reviewer: headers["X-Reviewer-Id"] ?: ""
                    }
                };
            }
            if path.endsWith("/decision-preparations") {
                json[] toCheck = [];
                foreach int i in 0 ..< self.prepRecords.length() {
                    toCheck.push({crmGuestRecordId: self.prepRecords[i], expectedModifiedTime: self.prepTimes[i]});
                }
                json prepared = {
                    reviewDecisionId: "RD-1",
                    caseId: "RC-1",
                    state: "REVIEW_DECISION_PREPARED",
                    action: core:pick(body, "action"),
                    crmRecordsToCheck: toCheck.clone(),
                    compareFields: ["firstName", "lastName", "dateOfBirth", "phone", "email", "guestIdentityId"],
                    crmPatch: self.crmPatch.clone()
                };
                Reply out = {status: 200, body: prepared};
                return out.clone();
            }
            if path.startsWith("/v1/review-decisions/") {
                if path.endsWith("/commit") && self.commitFailures > 0 {
                    self.commitFailures -= 1;
                    return {status: 503, body: {code: "INTERNAL_ERROR"}};
                }
                return {status: 200, body: {reviewDecisionId: "RD-1"}};
            }
            return {status: 404, body: {code: "NOT_FOUND"}};
        }
    }
}

# Behaves like Zoho behind zoho-sys-api: records by id, upsert by a unique field, COQL pages.
isolated class MemCrm {
    *CrmApi;
    private string[] calls = [];
    private map<map<json>> records = {};
    private int writeFailures = 0;
    private int seq = 1000;
    private json[][] & readonly coqlPages = [];
    private int coqlNext = 0;

    isolated function put(string module, map<json> rec0) {
        map<json> & readonly rec = rec0.cloneReadOnly();
        lock {
            self.records[module + "/" + core:text(rec["id"])] = rec.clone();
        }
    }

    isolated function recordOf(string module, string id) returns map<json>? {
        lock {
            return self.records[module + "/" + id].clone();
        }
    }

    isolated function setWriteFailures(int n) {
        lock {
            self.writeFailures = n;
        }
    }

    isolated function setCoqlPages(json[][] pages0) {
        json[][] & readonly pages = pages0.cloneReadOnly();
        lock {
            self.coqlPages = pages;
            self.coqlNext = 0;
        }
    }

    isolated function count(string prefix) returns int {
        lock {
            int n = 0;
            foreach string c in self.calls {
                if c.startsWith(prefix) {
                    n += 1;
                }
            }
            return n;
        }
    }

    isolated function total() returns int {
        lock {
            return self.calls.length();
        }
    }

    isolated function call(string method, string zohoPath, map<string> query0, json body0, string correlationId)
            returns Reply|error {
        json & readonly body = body0.cloneReadOnly();
        map<string> & readonly query = query0.cloneReadOnly();
        lock {
            self.calls.push(method + " " + zohoPath);
            if zohoPath.endsWith("/coql") {
                if self.coqlNext >= self.coqlPages.length() {
                    return {status: 200, body: {data: [], info: {more_records: false}}};
                }
                json[] & readonly page = self.coqlPages[self.coqlNext];
                self.coqlNext += 1;
                return {status: 200, body: {data: page, info: {more_records: false}}};
            }
            string module = re `/`.split(zohoPath)[3];
            if method == http:GET {
                json[] out = [];
                foreach string id in re `,`.split(query["ids"] ?: "") {
                    map<json>? r = self.records[module + "/" + id];
                    if r is map<json> {
                        out.push(r.clone());
                    }
                }
                return {status: 200, body: {data: out.clone()}};
            }
            if self.writeFailures > 0 {
                self.writeFailures -= 1;
                return {status: 500, body: {code: "INTERNAL_ERROR", message: "zoho down"}};
            }
            json rows = core:pick(body, "data");
            if rows !is json[] || rows.length() == 0 || rows[0] !is map<json> {
                return {status: 400, body: {code: "INVALID_DATA"}};
            }
            map<json> row = <map<json>>(<json[]>rows)[0];
            self.seq += 1;
            string modified = "2026-11-16T12:00:" + (self.seq % 60 < 10 ? "0" : "") + (self.seq % 60).toString() + "+00:00";
            string id = "";
            if zohoPath.endsWith("/upsert") {
                json keys = core:pick(body, "duplicate_check_fields");
                string keyField = keys is json[] && keys.length() > 0 ? core:text(keys[0]) : "";
                id = "";
                foreach [string, map<json>] [k, r] in self.records.entries() {
                    if k.startsWith(module + "/") && keyField != "" && r[keyField] == row[keyField] {
                        id = core:text(r["id"]);
                    }
                }
                if id == "" {
                    id = "Z" + self.seq.toString();
                }
            } else {
                id = core:text(row["id"]);
            }
            map<json> existing = {"id": id};
            foreach [string, json] [k, v] in (self.records[module + "/" + id] ?: {}).entries() {
                existing[k] = v.clone();
            }
            foreach [string, json] [k, v] in row.entries() {
                existing[k] = v;
            }
            existing["id"] = id;
            existing["Modified_Time"] = modified;
            self.records[module + "/" + id] = existing;
            return {
                status: 200,
                body: {
                    data: [
                        {
                            code: "SUCCESS",
                            status: "success",
                            details: {id, Modified_Time: modified}
                        }
                    ]
                }
            };
        }
    }
}

# Kafka stand-in.
isolated class MemBus {
    *EventBus;
    private json[] sent = [];
    private boolean down = false;

    isolated function setDown(boolean b) {
        lock {
            self.down = b;
        }
    }

    isolated function onTopic(string topic) returns json[] {
        lock {
            json[] out = [];
            foreach json s in self.sent {
                if core:pick(s, "topic") == topic {
                    out.push(core:pick(s, "event"));
                }
            }
            return out.clone();
        }
    }

    isolated function publish(string topic, string key, map<json> event0) returns error? {
        map<json> & readonly event = event0.cloneReadOnly();
        lock {
            if self.down {
                return error("broker unreachable");
            }
            self.sent.push({topic, key, event: event.clone()});
        }
    }
}

isolated function guestEvent(string guest, string modified, string currentGlobal = "") returns map<json> {
    map<json> e = {
        schemaVersion: "1.0",
        eventId: "EV-" + guest + "-" + modified,
        eventType: core:EVALUATION,
        idempotencyKey: "SEAWARE:S-" + guest + ":" + modified,
        correlationId: "CORR-" + guest,
        sourceSystem: "SEAWARE",
        sourceRecordId: "S-" + guest,
        crmGuestRecordId: guest,
        crmModifiedTime: modified,
        firstName: "Test",
        lastName: "Guest",
        sourceCode: "MOBAPP",
        agencyName: "AROYA CRUISES MAIN OFFICE"
    };
    if currentGlobal != "" {
        e["currentGlobalId"] = currentGlobal;
    }
    return e;
}
