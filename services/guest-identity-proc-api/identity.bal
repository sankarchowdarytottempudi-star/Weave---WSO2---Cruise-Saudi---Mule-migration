// POST /processGuestIdentity: every guest of the list gets a Seaware client and - for the channels
// that write to the CRM - a CRM contact with a guest id and a loyalty id.

import guest_identity_proc_api.core;

import ballerina/http;
import ballerina/log;
import aroya/integration_commons as commons;

# What the caller's headers say about a POST /processGuestIdentity request.
#
# + channel - Header client_channel
# + deviceId - Header client_device_id
# + realTime - Header client_realTime is "true": answer after Seaware, write the CRM afterwards
# + correlationId - The request's correlation id
type IdentityContext record {|
    string? channel;
    string? deviceId;
    boolean realTime;
    string correlationId;
|};

isolated function processGuestIdentity(http:Request request, string correlationId) returns http:Response|Stop {
    json|http:ClientError body = request.getJsonPayload();
    if body !is json[] {
        return stopWith(commons:BAD_REQUEST, "The body must be a JSON list of guests", correlationId);
    }
    IdentityContext & readonly ctx = {
        channel: commons:headerOf(request, "client_channel"),
        deviceId: commons:headerOf(request, "client_device_id"),
        realTime: commons:headerOf(request, "client_realTime") == "true",
        correlationId
    };
    check requireIdentityBackends(ctx.channel, correlationId);

    json[] results = [];
    int size = int:max(identityParallelism, 1);
    int index = 0;
    while index < body.length() {
        future<json>[] running = [];
        foreach json guest in body.slice(index, int:min(body.length(), index + size)) {
            future<json> one = start identityResult(guest.cloneReadOnly(), ctx);
            running.push(one);
        }
        foreach future<json> one in running {
            json|error result = wait one;
            results.push(result is error ? {"status": "error", "message": result.message()} : result);
        }
        index += size;
    }
    return jsonAnswer(200, results, correlationId);
}

# The backends a guest needs, checked before anything is written.
#
# + channel - The caller's channel
# + correlationId - The request's correlation id
# + return - 503 naming what is not set
isolated function requireIdentityBackends(string? channel, string correlationId) returns Stop? {
    check requireSet(correlationId, RESERVATION);
    check requireAgent(correlationId);
    if core:channelAllowed(channelCheck, channel) {
        check requireSet(correlationId, ZOHO, IDENTITY_SUPPORT);
    }
    return ();
}

isolated function identityResult(json & readonly guest, IdentityContext & readonly ctx) returns json {
    if guest !is map<json> & readonly {
        return {"status": "error", "message": "A guest must be a JSON object"};
    }
    json|Stop result = identityItem(guest, ctx);
    if result is Stop {
        json message = core:fieldOf(result.detail().body, "message");
        return {"status": "error", "message": core:has(message) ? core:textOf(message) : "The guest could not be processed"};
    }
    return result;
}

# One guest: CRM ids, Seaware client, CRM contact.
#
# + guest - The guest as sent
# + ctx - The caller's headers
# + return - The answer for the guest
isolated function identityItem(map<json> & readonly guest, IdentityContext & readonly ctx) returns json|Stop {
    string correlationId = ctx.correlationId;
    boolean crm = core:channelAllowed(channelCheck, ctx.channel);
    // Performance: the Seaware sign-in does not depend on the CRM ids, so it is opened while they are
    // worked out. When the CRM step stops, the session is closed and the same stop is answered.
    future<string|Stop> login = start seawareLogin(correlationId);
    string globalId = "";
    string loyaltyId = "";
    if crm {
        [string, string]|Stop ids = crmIds(guest, correlationId);
        if ids is Stop {
            string|Stop|error opened = wait login;
            if opened is string {
                future<()> _ = start seawareLogout(opened, correlationId);
            }
            return ids;
        }
        [globalId, loyaltyId] = ids;
    }
    // Mule writes "<loyalty id>|<guest id>" to the client's comments - "|" for the other channels.
    [string, string?] [clientId, problem] = check seawareClientWith(login, guest, loyaltyId + "|" + globalId,
            correlationId);
    if !crm {
        return core:clientOnlyAnswerOf(clientId);
    }
    if ctx.realTime {
        future<()> _ = start crmUpsertLater(guest, clientId, problem, globalId, loyaltyId, ctx);
        return core:clientOnlyAnswerOf(clientId);
    }
    return crmUpsert(guest, clientId, problem, globalId, loyaltyId, ctx);
}

# The guest id and loyalty id of a guest: those of the newest matching CRM contact, else new ones.
# The contacts already in the CRM are brought up to date on the way (Mule: guest_zoho-impl).
#
# + guest - The guest as sent
# + correlationId - The request's correlation id
# + return - [guest id, loyalty id]
isolated function crmIds(map<json> guest, string correlationId) returns [string, string]|Stop {
    // Performance: the two generated ids and the CRM search do not depend on each other, so they are
    // sent at the same time. Their results are looked at in the order Mule ran them (guest id, loyalty
    // id, search), so every answer and every stop is the one it was before.
    future<string|Stop> guestIdCall = start generatedId(generateGuestIdPath, "guestId", correlationId);
    future<string|Stop> loyaltyIdCall = start generatedId(generateLoyaltyIdPath, "loyaltyId", correlationId);
    future<json|Stop>? searchCall = ();
    if core:completeMatch(guest) {
        searchCall = start zohoSearch(core:searchCriteriaOf(guest), (), correlationId);
    }
    string globalId = check idSettled(guestIdCall, "guestId", correlationId);
    string loyaltyId = check idSettled(loyaltyIdCall, "loyaltyId", correlationId);
    json[] records = [];
    if searchCall is future<json|Stop> {
        json found = check settled(searchCall, "crm search", correlationId);
        records = core:listOf(core:fieldOf(found, "data"));
    }
    map<json>? selected = core:selectedRecordOf(records);
    if selected is map<json> {
        globalId = core:textOf(selected["Global_Guest_ID"]);
        loyaltyId = core:textOf(selected["Aroya_Loyalty_ID"]);
    }
    json[] updates = core:existingUpdatesOf(records, guest, globalId, loyaltyId);
    int index = 0;
    while index < updates.length() {
        json[] batch = updates.slice(index, int:min(updates.length(), index + 99));
        json answer = check zohoWrite(http:PUT, contactUpdatePath, {"data": batch}, correlationId);
        if core:isCrmError(answer) {
            log:printWarn("Existing CRM contacts were not all updated", correlationId = correlationId,
                    contacts = batch.length());
        }
        index += 99;
    }
    return [globalId, loyaltyId];
}

# The guest's Seaware client: found and updated, or created - in one Seaware session.
#
# + guest - The guest as sent
# + ids - Text for the client's comments
# + correlationId - The request's correlation id
# + return - [client id ("" when there is none), Seaware's error message if it sent one]
isolated function seawareClient(map<json> guest, string ids, string correlationId) returns [string, string?]|Stop {
    future<string|Stop> login = start seawareLogin(correlationId);
    return seawareClientWith(login, guest, ids, correlationId);
}

# The guest's Seaware client work in a session that is being opened; the session is closed after the
# answer is known (the close does not hold the answer up).
#
# + login - The sign-in that is under way
# + guest - The guest as sent
# + ids - Loyalty id and global guest id, for the client comments
# + correlationId - The request's correlation id
# + return - [client id, Seaware's problem if any]
isolated function seawareClientWith(future<string|Stop> login, map<json> guest, string ids, string correlationId)
        returns [string, string?]|Stop {
    string token = check tokenSettled(login, correlationId);
    [string, string?]|Stop result = seawareClientIn(token, guest, ids, correlationId);
    future<()> _ = start seawareLogout(token, correlationId);
    return result;
}

isolated function seawareClientIn(string token, map<json> guest, string ids, string correlationId)
        returns [string, string?]|Stop {
    json clients = ();
    if core:hasClientSearch(guest) {
        clients = check seawareIn(token, core:clientsQueryOf(guest), "client search", correlationId);
    } else {
        log:printWarn("Seaware client search skipped: the guest has no name, e-mail address or phone",
                correlationId = correlationId);
    }
    core:ClientPlan plan = core:clientPlanOf(guest, clients, ids);
    if plan.kind == "none" {
        return [plan.updateClient, ()];
    }
    json answer = check seawareIn(token, {"query": plan.query}, "client " + plan.kind, correlationId);
    [string, string] [updated, created] = core:clientKeysOf(answer);
    string? problem = core:firstSeawareError(answer);
    if problem is () {
        json message = core:fieldOf(core:listOf(core:fieldOf(answer, "data", "clientCreate", "errors")).length() > 0
                ? core:listOf(core:fieldOf(answer, "data", "clientCreate", "errors"))[0] : (), "message");
        problem = message is string ? message : ();
    }
    return [core:clientIdOf(updated, created), problem];
}

# The CRM contact of the guest, its copy in the guest store and its picture (Mule: guest-crm-upsert-impl).
#
# + guest - The guest as sent
# + clientId - Seaware client id from the Seaware step
# + problem - Seaware's error message, if it sent one
# + globalId - Guest id
# + loyaltyId - Loyalty id
# + ctx - The caller's headers
# + return - The answer for the guest
isolated function crmUpsert(map<json> & readonly guest, string clientId, string? problem, string globalId,
        string loyaltyId, IdentityContext & readonly ctx) returns json|Stop {
    string correlationId = ctx.correlationId;
    map<json>|error contact = core:crmRecordOf(guest, clientId, globalId, loyaltyId);
    if contact is error {
        return {"status": "error", "message": contact.message() + (problem is string ? ": " + problem : "")};
    }
    json answer = check zohoWrite(http:POST, contactUpsertPath, core:crmUpsertBodyOf(contact), correlationId);
    boolean failed = core:isCrmError(answer);
    string zohoId = core:crmContactIdOf(answer);
    if !failed {
        // Mule stores the guest in an async scope: the answer does not wait for it.
        future<()> _ = start storeGuest(contact.cloneReadOnly(), answer.cloneReadOnly(), ctx);
    }
    json image = ();
    json file = guest["file"];
    if file is string && file != "" && !failed && zohoId != "" {
        image = check zohoPhotoUpload(zohoId, file, correlationId);
    }
    return core:identityAnswerOf(answer, image, contact, core:textOf(contact["Client_ID"]));
}

isolated function crmUpsertLater(map<json> & readonly guest, string clientId, string? problem, string globalId,
        string loyaltyId, IdentityContext & readonly ctx) {
    json|Stop result = crmUpsert(guest, clientId, problem, globalId, loyaltyId, ctx);
    if result is Stop {
        log:printError("CRM contact was not written", correlationId = ctx.correlationId, status = result.detail().status);
    } else {
        log:printInfo("CRM contact written after the answer", correlationId = ctx.correlationId,
                status = core:textOf(core:fieldOf(result, "status")));
    }
}

isolated function storeGuest(map<json> & readonly contact, json & readonly crmAnswer, IdentityContext & readonly ctx) {
    string correlationId = ctx.correlationId;
    json rows = dbBestEffort(core:guestCoreUpsertOf(contact, crmAnswer), "guest core upsert", correlationId);
    map<json>? row = core:firstRowOf(rows);
    string guestCoreId = row is () ? "" : core:textOf(row["id"]);
    string? deviceId = ctx.deviceId;
    string? channel = ctx.channel;
    if guestCoreId != "" && deviceId is string && channel is string {
        _ = dbBestEffort(core:deviceLinkOf(guestCoreId, deviceId, channel), "device link", correlationId);
    }
}
