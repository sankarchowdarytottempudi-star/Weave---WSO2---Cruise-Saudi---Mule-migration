// GET /processGuestBookingInfo, POST /guest-profiles, POST and PUT /guest-profiles/{guestId}, POST /bookingLogin.

import guest_identity_proc_api.core;

import ballerina/http;
import ballerina/log;
import ballerina/time;
import aroya/integration_commons as commons;

// Zoho returns 200 contacts a page; this many pages are read at most.
const MAX_CRM_PAGES = 50;

isolated function bookingInfo(http:Request request, string correlationId) returns http:Response|Stop {
    string loyaltyId = (request.getQueryParamValue("aroyaloyaltyId") ?: "").trim();
    string guestId = (request.getQueryParamValue("globalGuestId") ?: "").trim();
    if loyaltyId == "" || guestId == "" {
        return stopWith(commons:BAD_REQUEST, "aroyaloyaltyId and globalGuestId are required", correlationId);
    }
    check requireSet(correlationId, ZOHO);
    json found = check zohoSearch(core:bookingInfoCriteriaOf(loyaltyId, guestId), (), correlationId);
    return jsonAnswer(200, core:bookingInfoOf(found), correlationId);
}

isolated function profileList(http:Request request, string correlationId) returns http:Response|Stop {
    json|http:ClientError body = request.getJsonPayload();
    map<json>? payload = body is http:ClientError ? () : core:requestFieldsOf(body);
    string identifier = payload is () ? "" : core:trimmed(payload["identifier"]).toLowerAscii();
    string? criteria = request.getQueryParamValue("criteria");
    if identifier == "" && (criteria is () || criteria.trim() == "") {
        return stopWith(commons:BAD_REQUEST, "identifier is required", correlationId);
    }
    int page = core:intOf(request.getQueryParamValue("page"), 1);
    int perPage = core:intOf(request.getQueryParamValue("perPage"), 10);
    if page < 1 || perPage < 1 {
        return stopWith(commons:BAD_REQUEST, "page and perPage must be 1 or more", correlationId);
    }
    check requireSet(correlationId, ZOHO);

    json[] contacts = [];
    int crmPage = 1;
    while true {
        json found = check zohoSearch(core:profileCriteriaOf(criteria, identifier), crmPage, correlationId);
        contacts.push(...core:listOf(core:fieldOf(found, "data")));
        if core:fieldOf(found, "info", "more_records") != true || crmPage >= MAX_CRM_PAGES {
            break;
        }
        crmPage += 1;
    }
    json[] latest = core:latestProfilesOf(contacts);
    json[] shown = core:pageOf(latest, page, perPage);

    // The pictures of the page's contacts are read at the same time.
    future<string?>[] pictures = [];
    foreach json contact in shown {
        future<string?> picture = start zohoPhoto(core:textOf(core:fieldOf(contact, "id")), correlationId);
        pictures.push(picture);
    }
    json[] profiles = [];
    foreach int i in 0 ..< shown.length() {
        string?|error picture = wait pictures[i];
        profiles.push(core:profileOf(shown[i], picture is error ? () : picture));
    }
    return jsonAnswer(200, core:profilesAnswerOf(profiles, page, perPage, latest.length()), correlationId);
}

isolated function trips(http:Request request, string clientId, string correlationId) returns http:Response|Stop {
    check requireSet(correlationId, RESERVATION);
    check requireAgent(correlationId);
    string deviceId = (commons:headerOf(request, "device_id") ?: commons:headerOf(request, "client_deviceid")
        ?: commons:headerOf(request, "client_device_id") ?: "").trim();
    if deviceId != "" {
        // Mule links the device on the side; a failure does not stop the trips.
        future<json> _ = start dbBestEffort(core:tripsDeviceLinkOf(deviceId,
                        commons:headerOf(request, "source-system") ?: "mobile", clientId).cloneReadOnly(),
                "device link", correlationId);
    }
    KeptTrips? kept = tripsKept(clientId);
    json answer;
    if kept is KeptTrips {
        answer = kept.answer;
    } else {
        answer = check seawareRead(core:reservationsQueryOf(clientId), "reservations", correlationId);
        string? problem = core:firstSeawareError(answer);
        if problem is string {
            return stopOf(502, {"status": "error", "message": problem});
        }
        tripsKeep(clientId, answer);
    }
    string today = time:utcToString(time:utcNow()).substring(0, 10);
    return jsonAnswer(200, core:tripsAnswerOf(answer, clientId, today), correlationId);
}

isolated function editProfile(http:Request request, string clientId, string correlationId) returns http:Response|Stop {
    json|http:ClientError payload = request.getJsonPayload();
    if payload !is map<json> {
        return stopWith(commons:BAD_REQUEST, "The body must be a JSON object", correlationId);
    }
    check requireSet(correlationId, RESERVATION, ZOHO);
    check requireAgent(correlationId);

    json seaware = check seawareRun(core:clientUpdateQueryOf(clientId, payload), "client update", correlationId);
    tripsForget(clientId);
    json crm = check zohoWrite(http:POST, contactUpsertPath,
            core:crmUpsertBodyOf(core:editContactOf(clientId, payload)), correlationId);
    // Performance: best effort and its result is not used, so it runs beside the rest of the request.
    future<json> _ = start dbBestEffort(core:editGuestCoreOf(clientId, payload, time:utcToString(time:utcNow()))
                    .cloneReadOnly(), "guest core update", correlationId);
    json image = ();
    json picture = payload["profileImage"];
    string contactId = core:crmContactIdOf(crm);
    if picture is string && picture != "" && contactId != "" {
        image = check zohoPhotoUpload(contactId, picture, correlationId);
    }
    [int, map<json>] [status, body] = core:editAnswerOf(payload, seaware, crm, image);
    string? problem = core:firstSeawareError(seaware);
    if problem is string && body["errorMessage"] == "" {
        body["errorMessage"] = problem;
    }
    if status != 200 {
        log:printWarn("Profile was not fully updated", correlationId = correlationId);
    }
    return jsonAnswer(status, body, correlationId);
}

isolated function bookingLogin(http:Request request, string correlationId) returns http:Response|Stop {
    json|http:ClientError payload = request.getJsonPayload();
    if payload !is map<json> {
        return stopWith(commons:BAD_REQUEST, "The body must be a JSON object", correlationId);
    }
    check requireSet(correlationId, DB);
    if deploymentTarget == "ship" {
        _ = check dbRun(core:bookingLoginShipGuestOf(payload), "guest upsert", correlationId);
        return jsonAnswer(200, check dbRun(core:bookingLoginShipDeviceOf(payload), "device link", correlationId),
                correlationId);
    }
    return jsonAnswer(200, check dbRun(core:bookingLoginShoreOf(payload), "device link", correlationId), correlationId);
}
