// Reviewer authentication and the CRM writes of an approved review decision (plan 10.4, 14.4).

import ballerina/crypto;
import ballerina/lang.array;

public const string ROLE_REVIEWER = "IDENTITY_REVIEWER";
public const string ROLE_SUPERVISOR = "IDENTITY_SUPERVISOR";

# A reviewer, as the Workbench vouched for them.
#
# + userId - CRM user id of the reviewer
# + roles - Identity roles (IDENTITY_REVIEWER, IDENTITY_SUPERVISOR, IDENTITY_AUDIT)
# + exp - Expiry, seconds since the epoch
public type Reviewer record {|
    string userId;
    string[] roles = [];
    int exp;
|};

# CRM module API names.
public type CrmModules record {|
    string guests = "Contacts";
    string identities = "Guest_Identities";
    string reviewCases = "Identity_Review_Cases";
|};

# One CRM write. `id` set = update of that record; `upsertKey` set = upsert by that unique field.
public type CrmWrite record {|
    string module;
    string id = "";
    string upsertKey = "";
    map<json> fields;
|};

isolated function fromBase64Url(string v) returns byte[]|error {
    string s = re `-`.replaceAll(re `_`.replaceAll(v.trim(), "/"), "+");
    int pad = (4 - s.length() % 4) % 4;
    foreach int _ in 0 ..< pad {
        s += "=";
    }
    return array:fromBase64(s);
}

isolated function sameText(string a, string b) returns boolean {
    // compares every character, so the time taken does not tell how much of a signature was right
    if a.length() != b.length() {
        return false;
    }
    int diff = 0;
    foreach int i in 0 ..< a.length() {
        diff = diff | (a.getCodePoint(i) ^ b.getCodePoint(i));
    }
    return diff == 0;
}

# The signature the Workbench backend puts on a reviewer context (hex HMAC-SHA256).
public isolated function signatureOf(string context, string secret) returns string|error =>
    (check crypto:hmacSha256(context.toBytes(), secret.toBytes())).toBase16();

# Verifies the reviewer context sent by the Workbench (X-Reviewer-Context, base64url JSON
# {"userId","roles","exp"}, signed in X-Reviewer-Signature with the shared secret).
#
# + context - X-Reviewer-Context
# + signature - X-Reviewer-Signature
# + secret - Shared secret; empty = review API switched off
# + nowSeconds - Now, seconds since the epoch
# + maxAgeSeconds - Longest accepted lifetime of a context
# + return - The reviewer, or an error saying why not
public isolated function reviewerOf(string context, string signature, string secret, int nowSeconds,
        int maxAgeSeconds) returns Reviewer|error {
    if secret == "" {
        return error("REVIEW_AUTH_NOT_CONFIGURED");
    }
    if context == "" || signature == "" {
        return error("REVIEWER_CONTEXT_MISSING");
    }
    if !sameText(check signatureOf(context, secret), signature.toLowerAscii()) {
        return error("REVIEWER_SIGNATURE_INVALID");
    }
    byte[] raw = check fromBase64Url(context);
    json body = check (check string:fromBytes(raw)).fromJsonString();
    Reviewer reviewer = check body.cloneWithType();
    if reviewer.userId.trim() == "" {
        return error("REVIEWER_CONTEXT_INVALID");
    }
    if reviewer.exp <= nowSeconds || reviewer.exp - nowSeconds > maxAgeSeconds {
        return error("REVIEWER_CONTEXT_EXPIRED");
    }
    return reviewer;
}

# Whether a reviewer may take an action (plan 15.3): reviewers decide, supervisors also reverse.
public isolated function mayDecide(Reviewer reviewer, string action) returns boolean {
    boolean supervisor = reviewer.roles.indexOf(ROLE_SUPERVISOR) is int;
    if action == "REVERSE_DECISION" {
        return supervisor;
    }
    return supervisor || reviewer.roles.indexOf(ROLE_REVIEWER) is int;
}

# Whether a reviewer may open a case (reviewers, supervisors and audit).
public isolated function mayView(Reviewer reviewer) returns boolean {
    foreach string r in reviewer.roles {
        if r == ROLE_REVIEWER || r == ROLE_SUPERVISOR || r == "IDENTITY_AUDIT" {
            return true;
        }
    }
    return false;
}

isolated function idOf(json v) returns string => text(v is map<json> ? v["id"] : v);

# The CRM writes of an approved review decision, in the order they are applied (plan 10.4 step 6):
# 1. the provisional identity retired as an alias of the surviving one, 2. household links on the
# identities, 3. the Guest (identity link, status, case), 4. the review case mirror.
# Python's crmPatch is applied as it is; a key this service does not know is refused, never guessed.
#
# + crmPatch - Python's approved instruction
# + guestRecordId - The case's incoming Guest (first of crmRecordsToCheck)
# + caseId - Review case id
# + reviewerId - Reviewer's CRM user id
# + reviewDecisionId - Review decision id
# + f - CRM field names
# + m - CRM module names
# + return - Writes in order, or an error
public isolated function reviewWritesOf(json crmPatch, string guestRecordId, string caseId, string reviewerId,
        string reviewDecisionId, CrmFields f = {}, CrmModules m = {}) returns CrmWrite[]|error {
    if crmPatch !is map<json> || guestRecordId == "" {
        return error("crmPatch is not an object, or the case has no Guest");
    }
    foreach string k in crmPatch.keys() {
        if [
            "identityStatus",
            "reviewCaseId",
            "reviewAction",
            "guestIdentityId",
            "aliasIdentityId",
            "householdWith",
            "householdId",
            "followUpDate",
            "globalId",
            "loyaltyId",
            "decisionType"
        ].indexOf(k) is () {
            return error("crmPatch key not known: " + k);
        }
    }
    string action = text(crmPatch["reviewAction"]);
    string target = idOf(crmPatch["guestIdentityId"]);
    string alias = idOf(crmPatch["aliasIdentityId"]);
    string household = text(crmPatch["householdId"]);
    CrmWrite[] out = [];
    if alias != "" && alias != target {
        map<json> a = {"Identity_Lifecycle": "ALIAS", "Decision_ID": reviewDecisionId};
        if target != "" {
            a["Surviving_Identity"] = {"id": target};
        }
        out.push({module: m.identities, id: alias, fields: a});
    }
    json members = crmPatch["householdWith"];
    if household != "" && members is json[] {
        string[] ids = target == "" ? [] : [target];
        foreach json h in members {
            string id = idOf(h);
            if id != "" && ids.indexOf(id) is () {
                ids.push(id);
            }
        }
        foreach string id in ids {
            out.push({module: m.identities, id, fields: {"Household_ID": household}});
        }
    }
    map<json> g = {};
    string status = text(crmPatch["identityStatus"]);
    if status != "" {
        g[f.identityStatus] = status;
    }
    if target != "" {
        g[f.guestIdentity] = {"id": target};
    }
    g[f.reviewCaseId] = text(crmPatch["reviewCaseId"]) == "" ? caseId : text(crmPatch["reviewCaseId"]);
    g[f.decisionType] = text(crmPatch["decisionType"]) == "" ? "MANUAL" : text(crmPatch["decisionType"]);
    g[f.decisionId] = reviewDecisionId;
    g[f.lastEvaluated] = now();
    if household != "" {
        g["Household_ID"] = household;
    }
    string globalId = text(crmPatch["globalId"]);
    string loyaltyId = text(crmPatch["loyaltyId"]);
    if globalId != "" && loyaltyId != "" {
        g[f.globalId] = globalId;
        g[f.loyaltyId] = loyaltyId;
    }
    out.push({module: m.guests, id: guestRecordId, fields: g});
    map<json> c = {
        "Name": caseId,
        "Case_ID": caseId,
        "Case_Status": action == "DEFER" ? "REVIEW_OPEN" : "REVIEW_COMMITTED",
        "Reviewer": {"id": reviewerId}
    };
    if action != "" {
        c["Last_Action"] = action;
    }
    string followUp = text(crmPatch["followUpDate"]);
    if followUp != "" {
        c["Follow_Up_Date"] = followUp.length() > 10 ? followUp.substring(0, 10) : followUp;
    }
    out.push({module: m.reviewCases, upsertKey: "Case_ID", fields: c});
    return out;
}
