// Guest Identity Resolution ingress (plan v2.1 section 14.1), used only when
// identityResolution.enabled is true. With the flag off none of this runs.

# Whether a guest is in the approved direct scope: its booking source code AND its agency are on the
# owner-approved lists (trimmed, case-insensitive). A guest without either value is out of scope and
# keeps today's processing.
#
# + guest - The guest as sent
# + sourceCodeField - Field of the guest that holds the booking source code
# + agencyNameField - Field of the guest that holds the agency name
# + sourceCodes - Approved source codes
# + agencyNames - Approved agency names
# + return - In scope
public isolated function inResolutionScope(map<json> guest, string sourceCodeField, string agencyNameField,
        string[] sourceCodes, string[] agencyNames) returns boolean {
    string sourceCode = textOf(guest[sourceCodeField]).trim().toUpperAscii();
    string agency = textOf(guest[agencyNameField]).trim().toUpperAscii();
    if sourceCode == "" || agency == "" {
        return false;
    }
    boolean sourceOk = false;
    foreach string c in sourceCodes {
        sourceOk = sourceOk || c.trim().toUpperAscii() == sourceCode;
    }
    boolean agencyOk = false;
    foreach string a in agencyNames {
        agencyOk = agencyOk || a.trim().toUpperAscii() == agency;
    }
    return sourceOk && agencyOk;
}

# The CRM contact of an in-scope guest: no IDs (Python decides them later), status
# PENDING_IDENTITY, the source system, and - when a CRM field is named for it - the source code.
#
# + contact - The contact as today's flow builds it
# + sourceSystem - Source system (SEAWARE)
# + sourceCode - The booking source code
# + sourceCodeCrmField - CRM field for the source code; "" = not written
# + return - The contact to upsert
public isolated function pendingContactOf(map<json> contact, string sourceSystem, string sourceCode,
        string sourceCodeCrmField) returns map<json> {
    map<json> out = {};
    foreach [string, json] [k, v] in contact.entries() {
        if k != "Global_Guest_ID" && k != "Aroya_Loyalty_ID" {
            out[k] = v;
        }
    }
    out["Identity_Status"] = "PENDING_IDENTITY";
    out["Direct_Scope"] = true;
    out["Source_System"] = sourceSystem;
    if sourceCodeCrmField != "" && sourceCode != "" {
        out[sourceCodeCrmField] = sourceCode;
    }
    return out;
}

isolated function putTrimmed(map<json> m, string key, json v) {
    string t = textOf(v).trim();
    if t != "" {
        m[key] = t;
    }
}

# The full snapshot event guest.identity.evaluation.requested.v1 (schema 1.0) of a guest whose
# contact was just upserted, or () when the CRM answer has no record id or Modified Time.
#
# + guest - The guest as sent
# + contact - The contact that was upserted
# + upsertAnswer - The CRM answer
# + sourceSystem - Source system
# + sourceCode - Booking source code
# + agencyName - Agency name
# + correlationId - Correlation id
# + eventId - New event id
# + return - The event
public isolated function evaluationEventOf(map<json> guest, map<json> contact, json upsertAnswer, string sourceSystem,
        string sourceCode, string agencyName, string correlationId, string eventId) returns map<json>? {
    string crmId = crmContactIdOf(upsertAnswer);
    string modified = textOf(fieldOf(firstRecordOf(upsertAnswer), "details", "Modified_Time"));
    string sourceRecordId = textOf(contact["Client_ID"]);
    if crmId == "" || modified == "" || sourceRecordId == "" {
        return ();
    }
    map<json> e = {
        "schemaVersion": "1.0",
        "eventId": eventId,
        "eventType": "GUEST_IDENTITY_EVALUATION_REQUESTED",
        "idempotencyKey": sourceSystem + ":" + sourceRecordId + ":" + modified,
        "correlationId": correlationId,
        "sourceSystem": sourceSystem,
        "sourceRecordId": sourceRecordId,
        "crmGuestRecordId": crmId,
        "crmModifiedTime": modified
    };
    putTrimmed(e, "firstName", contact["First_Name"]);
    putTrimmed(e, "lastName", contact["Last_Name"]);
    putTrimmed(e, "dateOfBirth", contact["Date_of_Birth"]);
    putTrimmed(e, "phone", contact["Mobile"]);
    putTrimmed(e, "email", contact["Email"]);
    putTrimmed(e, "countryCode", guest["countryOfResidenceKey"]);
    putTrimmed(e, "citizenshipCode", guest["nationalityKey"]);
    putTrimmed(e, "sourceCode", sourceCode);
    putTrimmed(e, "agencyName", agencyName);
    e["active"] = true;
    return e;
}
