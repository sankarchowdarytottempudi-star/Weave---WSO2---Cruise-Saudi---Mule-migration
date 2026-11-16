// Pure functions of the Guest Identity Resolution integration (plan v2.1, sections 10, 11, 14).
// No I/O here: everything is testable without CRM, Kafka or the Python service.
//
// The Integration Service owns every CRM read and write; it never decides an identity. Python's
// decision and its crmPatch are applied as they are (plan 11.7: "opaque approved instruction").

import ballerina/crypto;
import ballerina/time;
import ballerina/uuid;

public const string SCHEMA_VERSION = "1.0";
public const string EVALUATION = "GUEST_IDENTITY_EVALUATION_REQUESTED";
public const string REEVALUATION = "GUEST_IDENTITY_REEVALUATION_REQUESTED";
public const string PENDING_IDENTITY = "PENDING_IDENTITY";
public const string CRM_DIRECT = "CRM_DIRECT";

# Direct scope (owner-approved): the booking came through a direct source code AND the agency is
# one of AROYA's own selling entities. Values are compared after trim + upper case.
public type DirectScope record {|
    string[] sourceCodes = ["INT-ASSC", "INT-CON", "NEWINT-CON", "MOBAPP", "WHATSAPP", "IN HOUSE"];
    string[] agencyNames = [
        "AROYA CRUISES MAIN OFFICE",
        "AROYA CRUISES MAIN OFFICE USD",
        "AROYA CRUISES MAIN OFFICE EUR",
        "AROYA CRUISES MAIN OFFICE GBP",
        "FUTURE CRUISES",
        "RIYADH SEASON",
        "WHATSAPP"
    ];
|};

# CRM field API names (contracts/crm/zoho-crm-configuration-spec.yaml). Configurable because Zoho
# confirms the final API name of a new field only when it is created.
public type CrmFields record {|
    string firstName = "First_Name";
    string lastName = "Last_Name";
    string dateOfBirth = "Date_of_Birth";
    string phone = "Mobile";
    string email = "Email";
    string country = "Country";
    string nationality = "Nationality";
    string sourceSystem = "Source_System";
    string sourceRecordId = "Client_ID";
    string sourceCode = "Lead_Source";
    string agency = "Account_Name";
    string globalId = "Global_Guest_ID";
    string loyaltyId = "Aroya_Loyalty_ID";
    string guestIdentity = "Guest_Identity";
    string identityStatus = "Identity_Status";
    string decisionType = "Identity_Decision_Type";
    string decisionId = "Identity_Decision_ID";
    string reviewCaseId = "Identity_Review_Case_ID";
    string ruleVersion = "Identity_Rule_Version";
    string reasonCodes = "Identity_Reason_Codes";
    string provisional = "Identity_Provisional";
    string lastEvaluated = "Identity_Last_Evaluated";
    string directScope = "Direct_Scope";
    # Contact field that keeps the correlation id of the last decision; "" = not kept (not in the CRM spec).
    string correlationId = "";
|};

public isolated function text(json v) returns string {
    if v is string {
        return v;
    }
    return v is () ? "" : v.toString();
}

public isolated function pick(json v, string... path) returns json {
    json current = v;
    foreach string name in path {
        if current is map<json> {
            current = current[name];
        } else {
            return ();
        }
    }
    return current;
}

isolated function norm(string v) returns string => v.trim().toUpperAscii();

isolated function containsNorm(string[] list, string v) returns boolean {
    foreach string c in list {
        if norm(c) == v {
            return true;
        }
    }
    return false;
}

# True when the booking is in the approved direct scope (both conditions).
#
# + sourceCode - Booking source code
# + agencyName - Agency on the reservation
# + scope - The approved lists
# + return - In scope
public isolated function inDirectScope(string sourceCode, string agencyName, DirectScope scope) returns boolean {
    string s = norm(sourceCode);
    string a = norm(agencyName);
    if s == "" || a == "" {
        return false;
    }
    return containsNorm(scope.sourceCodes, s) && containsNorm(scope.agencyNames, a);
}

# The idempotency key of an event: source system + source record id + CRM Modified Time (plan 9.3).
public isolated function idempotencyKeyOf(string sourceSystem, string sourceRecordId, string crmModifiedTime)
        returns string => sourceSystem + ":" + sourceRecordId + ":" + crmModifiedTime;

isolated function putIfText(map<json> m, string key, json v) {
    string t = text(v).trim();
    if t != "" {
        m[key] = t;
    }
}

# The full versioned identity snapshot event (plan 11.2) of one CRM Guest record.
#
# + rec - CRM Guest record (Zoho JSON)
# + eventType - EVALUATION or REEVALUATION
# + fallbackSourceSystem - Source system when the record carries none (CRM_DIRECT for direct CRM guests)
# + correlationId - Correlation id
# + f - CRM field names
# + return - The event
public isolated function snapshotEventOf(map<json> rec, string eventType, string fallbackSourceSystem,
        string correlationId, CrmFields f = {}) returns map<json> {
    string recordId = text(rec["id"]);
    string sourceSystem = text(rec[f.sourceSystem]).trim();
    string sourceRecordId = text(rec[f.sourceRecordId]).trim();
    if sourceSystem == "" {
        sourceSystem = fallbackSourceSystem;
    }
    if sourceRecordId == "" || sourceSystem == CRM_DIRECT {
        sourceRecordId = recordId;
    }
    string modified = text(rec["Modified_Time"]);
    map<json> e = {
        "schemaVersion": SCHEMA_VERSION,
        "eventId": uuid:createType4AsString(),
        "eventType": eventType,
        "idempotencyKey": idempotencyKeyOf(sourceSystem, sourceRecordId, modified),
        "correlationId": correlationId,
        "sourceSystem": sourceSystem,
        "sourceRecordId": sourceRecordId,
        "crmGuestRecordId": recordId,
        "crmModifiedTime": modified
    };
    putIfText(e, "firstName", rec[f.firstName]);
    putIfText(e, "lastName", rec[f.lastName]);
    putIfText(e, "dateOfBirth", rec[f.dateOfBirth]);
    putIfText(e, "phone", rec[f.phone]);
    putIfText(e, "email", rec[f.email]);
    putIfText(e, "countryCode", rec[f.country]);
    putIfText(e, "citizenshipCode", rec[f.nationality]);
    putIfText(e, "sourceCode", rec[f.sourceCode]);
    json agency = rec[f.agency];
    putIfText(e, "agencyName", agency is map<json> ? agency["name"] : agency);
    putIfText(e, "currentGlobalId", rec[f.globalId]);
    putIfText(e, "currentLoyaltyId", rec[f.loyaltyId]);
    json identity = rec[f.guestIdentity];
    putIfText(e, "currentIdentityId", identity is map<json> ? identity["id"] : identity);
    e["active"] = true;
    return e;
}

# The CRM fields read for a freshness check and for snapshots.
public isolated function snapshotFieldsOf(CrmFields f = {}) returns string[] => [
    f.firstName,
    f.lastName,
    f.dateOfBirth,
    f.phone,
    f.email,
    f.country,
    f.nationality,
    f.sourceSystem,
    f.sourceRecordId,
    f.sourceCode,
    f.agency,
    f.globalId,
    f.loyaltyId,
    f.guestIdentity,
    f.identityStatus,
    "Modified_Time"
];

# The Guest Identities record for a pair the decision reserved (plan 7.2).
#
# + decision - Python's decision
# + return - The CRM record, or () when the decision reserved no new pair
public isolated function identityRecordOf(map<json> decision) returns map<json>? {
    string globalId = text(decision["globalId"]);
    string loyaltyId = text(decision["loyaltyId"]);
    if globalId == "" || loyaltyId == "" || text(decision["crmIdentityRecordId"]) != "" {
        return ();
    }
    boolean provisional = decision["provisional"] == true;
    string decisionType = text(decision["decisionType"]);
    return {
        "Name": globalId,
        "Global_ID": globalId,
        "Loyalty_ID": loyaltyId,
        "Identity_Lifecycle": provisional ? "PROVISIONAL" : "ACTIVE",
        "Pair_Integrity": "COMPLETE",
        "Created_By_Process": provisional ? "REVIEW" : (decisionType.startsWith("CERTAIN") ? "CERTAIN" : "NEW"),
        "Rule_Version": text(decision["ruleVersion"]),
        "Decision_ID": text(decision["decisionId"])
    };
}

isolated function nowText() returns string {
    string t = time:utcToString(time:utcNow());
    // Zoho datetime: yyyy-MM-ddTHH:mm:ss+00:00 (no fractions)
    int? dot = t.indexOf(".");
    return (dot is int ? t.substring(0, dot) : t.substring(0, t.length() - 1)) + "+00:00";
}

# The fields written on the CRM Guest for a decision (plan 7.1, 14.1 step 7).
#
# + decision - Python's decision
# + identityRecordId - The CRM Guest Identity record id (existing or just created), or ""
# + correlationId - Correlation id
# + f - CRM field names
# + return - Fields to update
public isolated function contactPatchOf(map<json> decision, string identityRecordId, string correlationId,
        CrmFields f = {}) returns map<json> {
    map<json> p = {};
    p[f.identityStatus] = text(decision["identityStatus"]);
    p[f.decisionType] = text(decision["decisionType"]);
    p[f.decisionId] = text(decision["decisionId"]);
    p[f.ruleVersion] = text(decision["ruleVersion"]);
    json codes = decision["reasonCodes"];
    string joined = "";
    if codes is json[] {
        foreach json c in codes {
            joined += (joined == "" ? "" : ", ") + text(c);
        }
    }
    p[f.reasonCodes] = joined;
    p[f.provisional] = decision["provisional"] == true;
    p[f.lastEvaluated] = nowText();
    if f.correlationId != "" {
        p[f.correlationId] = correlationId;
    }
    string caseId = text(decision["reviewCaseId"]);
    if caseId != "" {
        p[f.reviewCaseId] = caseId;
    }
    if identityRecordId != "" {
        p[f.guestIdentity] = {"id": identityRecordId};
    }
    string globalId = text(decision["globalId"]);
    string loyaltyId = text(decision["loyaltyId"]);
    if globalId != "" && loyaltyId != "" {
        p[f.globalId] = globalId;
        p[f.loyaltyId] = loyaltyId;
    }
    return p;
}

# The review case mirror record in CRM (audit only; PostgreSQL is the source of truth).
public isolated function reviewCaseRecordOf(map<json> decision, string guestRecordId, string identityRecordId)
        returns map<json>? {
    string caseId = text(decision["reviewCaseId"]);
    if caseId == "" {
        return ();
    }
    map<json> r = {
        "Name": caseId,
        "Case_ID": caseId,
        "Guest": {"id": guestRecordId},
        "Priority": text(decision["reviewPriority"]) == "HIGH" ? "HIGH" : "NORMAL",
        "Case_Status": "REVIEW_OPEN"
    };
    string kind = kindOf(text(decision["decisionType"]));
    if kind != "" {
        r["Case_Kind"] = kind;
    }
    if identityRecordId != "" {
        r["Provisional_Identity"] = {"id": identityRecordId};
    }
    return r;
}

isolated function kindOf(string decisionType) returns string {
    match decisionType {
        "MULTIPLE_IDENTITY" => {
            return "MULTIPLE_IDENTITY_CONFLICT";
        }
        "FOUR_FIELD" => {
            return "FOUR_FIELD_REVIEW";
        }
        "PAIR_REPAIR" => {
            return "PAIR_REPAIR";
        }
        "GUARDRAIL" => {
            return "GUARDRAIL";
        }
    }
    return "";
}

# One record that failed the final freshness check.
public type FreshnessProblem record {|
    string crmGuestRecordId;
    string reason;
|};

# Compares the one final CRM read with what the reviewer saw (plan 10.4 step 4): a missing record,
# a different Modified Time, or a different identity link is a freshness failure. Any change to the
# five identity fields also changes Modified Time, so Modified Time equality covers them.
#
# + toCheck - [{crmGuestRecordId, expectedModifiedTime, expectedIdentityId?}]
# + crmRecords - Records read from CRM
# + f - CRM field names
# + return - Problems (empty = fresh)
public isolated function freshnessProblemsOf(json toCheck, map<json>[] crmRecords, CrmFields f = {})
        returns FreshnessProblem[] {
    map<map<json>> byId = {};
    foreach map<json> r in crmRecords {
        byId[text(r["id"])] = r;
    }
    FreshnessProblem[] out = [];
    if toCheck !is json[] {
        return out;
    }
    foreach json c in toCheck {
        string id = text(pick(c, "crmGuestRecordId"));
        map<json>? r = byId[id];
        if r is () {
            out.push({crmGuestRecordId: id, reason: "RECORD_MISSING"});
            continue;
        }
        if !sameInstant(text(r["Modified_Time"]), text(pick(c, "expectedModifiedTime"))) {
            out.push({crmGuestRecordId: id, reason: "MODIFIED_TIME_CHANGED"});
            continue;
        }
        json expectedLink = pick(c, "expectedIdentityId");
        if expectedLink !is () {
            json link = r[f.guestIdentity];
            string current = text(link is map<json> ? link["id"] : link);
            if current != text(expectedLink) {
                out.push({crmGuestRecordId: id, reason: "IDENTITY_LINK_CHANGED"});
            }
        }
    }
    return out;
}

# True when two timestamps are the same instant (Zoho answers +03:00, the reviewer may hold Z).
public isolated function sameInstant(string a, string b) returns boolean {
    if a == b {
        return true;
    }
    time:Utc|error x = time:utcFromString(withSeconds(a));
    time:Utc|error y = time:utcFromString(withSeconds(b));
    return x is time:Utc && y is time:Utc && time:utcDiffSeconds(x, y) == 0d;
}

isolated function withSeconds(string t) returns string {
    // "2026-11-16T10:20:30+03:00" is accepted as it is; a date-time without seconds gets ":00".
    return t.length() == 16 ? t + ":00Z" : t;
}

# A DLQ record (contracts/events/guest-identity-processing-dlq.v1).
public isolated function dlqEventOf(map<json> original, string topic, string stage, string errorCode,
        int? httpStatus, boolean retryable, int attempts, string firstFailure, string decisionId) returns map<json> {
    map<json> d = {
        "schemaVersion": SCHEMA_VERSION,
        "eventId": uuid:createType4AsString(),
        "correlationId": text(original["correlationId"]),
        "originalTopic": topic,
        "originalEventId": text(original["eventId"]),
        "crmGuestRecordId": text(original["crmGuestRecordId"]),
        "failureStage": stage,
        "errorCode": errorCode,
        "retryable": retryable,
        "attempts": attempts,
        "firstFailureTime": firstFailure,
        "lastFailureTime": nowText(),
        "payloadHash": payloadHashOf(original),
        "replayable": retryable
    };
    string key = text(original["idempotencyKey"]);
    if key != "" {
        d["idempotencyKey"] = key;
    }
    if decisionId != "" {
        d["decisionId"] = decisionId;
    }
    if httpStatus is int {
        d["httpStatus"] = httpStatus;
    }
    return d;
}

# SHA-256 of an event, so a DLQ record never carries personal data.
public isolated function payloadHashOf(json v) returns string =>
    crypto:hashSha256(v.toJsonString().toBytes()).toBase16();

public isolated function now() returns string => nowText();

# A record id shown in logs: last 4 characters only.
public isolated function masked(string id) returns string => id.length() <= 4 ? "****" : "…" + id.substring(id.length() - 4);
