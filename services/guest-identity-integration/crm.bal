// CRM operations used by the worker, the review API and the reconciliation. Every one is a single
// zoho-sys-api call; none of them decides anything about an identity.

import guest_identity_integration.core;

import ballerina/http;

# A CRM call that did not do what was asked.
#
# + status - HTTP status of the reply (0 = not reached)
# + code - Zoho error code, when there was one
public type CrmErrorDetail record {|
    int status;
    string code = "";
|};

public type CrmError distinct error<CrmErrorDetail>;

isolated function crmPath(string module, string tail = "") returns string =>
    "/crm/" + crmApiVersion + "/" + module + tail;

isolated function crmFailure(string what, Reply|error r) returns CrmError {
    if r is error {
        return error CrmError(what + ": CRM not reached", status = 0);
    }
    json first = core:pick(r.body, "data");
    string code = first is json[] && first.length() > 0 ? core:text(core:pick(first[0], "code"))
        : core:text(core:pick(r.body, "code"));
    return error CrmError(what + ": CRM answered " + r.status.toString(), status = r.status, code = code);
}

# The first data item of a write reply, when it succeeded.
isolated function writtenOf(Reply|error r, string what) returns map<json>|CrmError {
    if r is error || r.status >= 300 {
        return crmFailure(what, r);
    }
    json items = core:pick(r.body, "data");
    if items is json[] && items.length() > 0 && items[0] is map<json> {
        map<json> item = <map<json>>items[0];
        if core:text(item["status"]) == "success" || core:text(item["code"]) == "SUCCESS" {
            return item;
        }
    }
    return crmFailure(what, r);
}

# Updates one record. Workflows are not triggered (trigger: []), so Integration's own writes never
# fire the "identity field changed" webhook.
#
# + crm - CRM
# + module - Module API name
# + id - Record id
# + fields - Fields to set
# + correlationId - Correlation id
# + return - The record's new Modified_Time ("" when Zoho did not say), or a CrmError
isolated function crmUpdate(CrmApi crm, string module, string id, map<json> fields, string correlationId)
        returns string|CrmError {
    map<json> rec = {...fields};
    rec["id"] = id;
    map<json> item = check writtenOf(crm.call(http:PUT, crmPath(module), {}, {"data": [rec], "trigger": []},
            correlationId), "update " + module);
    return core:text(core:pick(item, "details", "Modified_Time"));
}

# Upserts one record by a unique field.
#
# + return - The record id, or a CrmError
isolated function crmUpsert(CrmApi crm, string module, string uniqueField, map<json> fields, string correlationId)
        returns string|CrmError {
    map<json> item = check writtenOf(crm.call(http:POST, crmPath(module, "/upsert"), {},
            {"data": [fields], "duplicate_check_fields": [uniqueField], "trigger": []}, correlationId),
            "upsert " + module);
    string id = core:text(core:pick(item, "details", "id"));
    if id == "" {
        return error CrmError("upsert " + module + ": no record id in the answer", status = 200);
    }
    return id;
}

# Applies one planned write.
isolated function crmApply(CrmApi crm, core:CrmWrite w, string correlationId) returns string|CrmError {
    if w.id != "" {
        return crmUpdate(crm, w.module, w.id, w.fields, correlationId);
    }
    return crmUpsert(crm, w.module, w.upsertKey, w.fields, correlationId);
}

# Reads records by id in ONE call (GET /crm/vN/Contacts?ids=a,b,c&fields=...).
#
# + return - The records found (missing ids are simply absent), or a CrmError
isolated function crmReadByIds(CrmApi crm, string module, string[] ids, string[] fields, string correlationId)
        returns map<json>[]|CrmError {
    string idList = "";
    foreach string id in ids {
        idList += (idList == "" ? "" : ",") + id;
    }
    string fieldList = "";
    foreach string f in fields {
        fieldList += (fieldList == "" ? "" : ",") + f;
    }
    Reply|error r = crm.call(http:GET, crmPath(module), {"ids": idList, "fields": fieldList}, (), correlationId);
    if r is error || r.status >= 300 {
        return crmFailure("read " + module, r);
    }
    return recordsOf(r.body);
}

isolated function recordsOf(json body) returns map<json>[] {
    map<json>[] out = [];
    json items = core:pick(body, "data");
    if items is json[] {
        foreach json i in items {
            if i is map<json> {
                out.push(i);
            }
        }
    }
    return out;
}

# One COQL page.
#
# + return - Records and whether more pages follow, or a CrmError
isolated function crmQuery(CrmApi crm, string query, string correlationId) returns [map<json>[], boolean]|CrmError {
    Reply|error r = crm.call(http:POST, "/crm/" + crmApiVersion + "/coql", {}, {"select_query": query}, correlationId);
    if r is error || r.status >= 300 {
        return crmFailure("query", r);
    }
    return [recordsOf(r.body), core:pick(r.body, "info", "more_records") == true];
}
