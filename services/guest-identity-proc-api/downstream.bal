// Calls to the backends of guest-identity-proc-api. Every function either returns its result or a
// Stop: the answer that ends the operation.

import guest_identity_proc_api.core;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/time;
import aroya/integration_commons as commons;

const RESERVATION = "reservationProcApi";
const ZOHO = "zohoSysApi";
const IDENTITY_SUPPORT = "identitySupportExpApi";
const DB = "dbSystemApi";
const EMAIL = "emailSysApi";
const CMS = "cmsContentApi";

final http:Client reservationClient = check commons:newDownstreamClient(reservationProcApi);
final http:Client zohoClient = check commons:newDownstreamClient(zohoSysApi);
final http:Client identitySupportClient = check commons:newDownstreamClient(identitySupportExpApi);
final http:Client dbSysClient = check commons:newDownstreamClient(dbSystemApi);
final http:Client emailClient = check commons:newDownstreamClient(emailSysApi);
final http:Client cmsClient = check commons:newDownstreamClient(cmsContentApi);

# The answer that ends an operation early.
#
# + status - HTTP status
# + body - Answer body
# + headers - Extra answer headers
type StopDetail record {|
    int status;
    json body;
    map<string> headers = {};
|};

type Stop distinct error<StopDetail>;

# A reply of a backend.
#
# + status - HTTP status
# + body - Body as JSON; `()` when it is empty or not JSON
type Reply record {|
    int status;
    json body;
|};

isolated function stopOf(int status, json body, map<string> headers = {}) returns Stop =>
    error Stop("stopped", status = status, body = body, headers = headers);

isolated function stopWith(string errorType, string message, string correlationId) returns Stop {
    commons:ErrorEnvelope envelope = commons:envelopeOf(errorType, message, correlationId);
    return stopOf(envelope.statusCode, envelope.toJson());
}

isolated function jsonAnswer(int status, json body, string correlationId, map<string> extraHeaders = {})
        returns http:Response {
    http:Response response = new;
    response.statusCode = status;
    response.setJsonPayload(body);
    response.setHeader(commons:CORRELATION_HEADER, correlationId);
    foreach [string, string] [name, value] in extraHeaders.entries() {
        response.setHeader(name, value);
    }
    return response;
}

# The HTTP answer of an operation's outcome.
#
# + result - The operation's answer, or what stopped it
# + operation - Name of the operation, for the log
# + correlationId - The request's correlation id
# + began - Monotonic clock reading when the operation started
# + return - The answer for the caller
isolated function answered(http:Response|Stop result, string operation, string correlationId, decimal began)
        returns http:Response {
    if result is http:Response {
        log:printInfo("Operation finished", correlationId = correlationId, operation = operation,
                status = result.statusCode, durationMs = millisSince(began));
        if result.statusCode >= 500 {
            json|http:ClientError body = result.getJsonPayload();
            mailError(operation, result.statusCode, body is json ? body : (), correlationId);
        }
        return result;
    }
    StopDetail detail = result.detail();
    log:printWarn("Operation stopped", correlationId = correlationId, operation = operation, status = detail.status,
            durationMs = millisSince(began));
    // Mule Global_Error_Handler: an error e-mail for a failure (switched off unless set in the settings)
    mailError(operation, detail.status, detail.body, correlationId);
    return jsonAnswer(detail.status, detail.body, correlationId, detail.headers);
}

# + began - A reading of the monotonic clock
# + return - Milliseconds since then
isolated function millisSince(decimal began) returns int => <int>((time:monotonicNow() - began) * 1000);

isolated function addressOf(string setting) returns string {
    match setting {
        RESERVATION => {
            return reservationProcApi.url;
        }
        ZOHO => {
            return zohoSysApi.url;
        }
        IDENTITY_SUPPORT => {
            return identitySupportExpApi.url;
        }
        DB => {
            return dbSystemApi.url;
        }
        EMAIL => {
            return emailSysApi.url;
        }
        _ => {
            return cmsContentApi.url;
        }
    }
}

isolated function isSet(string setting) returns boolean => !core:isPlaceholderAddress(addressOf(setting));

isolated function addressesNotSet() returns string[] =>
    from string name in [RESERVATION, ZOHO, IDENTITY_SUPPORT, DB, EMAIL, CMS]
    where !isSet(name)
    select name;

# Checks, before anything is written, that every backend an operation needs has an address.
#
# + correlationId - The request's correlation id
# + settings - Names of the backend settings the operation needs
# + return - 503 naming the first one that is not set
isolated function requireSet(string correlationId, string... settings) returns Stop? {
    foreach string setting in settings {
        if !isSet(setting) {
            return stopWith(commons:SERVICE_UNAVAILABLE, "The backend address is not set: " + setting + ".url",
                    correlationId);
        }
    }
    return ();
}

# Sends a JSON request. With `repeat`, a backend that cannot be reached (or answers 502 / 504) is
# tried again `httpRetryCount` times, `httpRetryFrequencySeconds` apart (Mule: until-successful).
#
# + backend - Name of the backend setting, for the log and the error answer
# + httpClient - Client of the backend
# + method - HTTP method
# + path - Path and query
# + body - JSON body; `()` for none
# + headers - Extra headers
# + correlationId - The request's correlation id
# + repeat - True to try again when the backend cannot be reached
# + step - What the call is for, for the log
# + return - The backend's reply, or the answer when it could not be reached
isolated function send(string backend, http:Client httpClient, string method, string path, json body,
        map<string> headers, string correlationId, boolean repeat, string step = "") returns Reply|Stop {
    map<string> out = {"Accept": "application/json"};
    foreach [string, string] [name, value] in headers.entries() {
        out[name] = value;
    }
    out[commons:CORRELATION_HEADER] = correlationId;
    int attempts = repeat ? int:max(httpRetryCount, 0) + 1 : 1;
    string errorType = commons:CONNECTIVITY;
    foreach int attempt in 1 ... attempts {
        decimal began = time:monotonicNow();
        http:Response|http:ClientError reply;
        if method == http:GET {
            reply = httpClient->get(path, out);
        } else {
            http:Request request = new;
            if body !is () {
                request.setJsonPayload(body);
            }
            foreach [string, string] [name, value] in out.entries() {
                request.setHeader(name, value);
            }
            reply = httpClient->execute(method, path, request);
        }
        if reply is http:Response && !(repeat && (reply.statusCode == 502 || reply.statusCode == 504)) {
            json|http:ClientError payload = reply.getJsonPayload();
            // One line per backend call: where the time of a request goes.
            log:printInfo("Backend answered", correlationId = correlationId, backend = backend, step = step,
                    status = reply.statusCode, durationMs = millisSince(began));
            return {status: reply.statusCode, body: payload is json ? payload : ()};
        }
        errorType = reply is http:ClientError ? commons:errorTypeOfClientError(reply)
            : commons:errorTypeOfStatus((<http:Response>reply).statusCode);
        log:printWarn("Backend could not be reached", correlationId = correlationId, backend = backend, step = step,
                attempt = attempt, attempts = attempts, errorType = errorType, durationMs = millisSince(began));
        if attempt < attempts {
            runtime:sleep(httpRetryFrequencySeconds);
        }
    }
    return stopWith(errorType, "The backend could not be reached: " + backend, correlationId);
}

// ---------------------------------------------------------------------------------------------
// Zoho CRM (through zoho-sys-api)
// Mule (zoho_accessToken.xml): the old app got its own Zoho token (zoho_getAccessTokenSub_Flow posts
// grant_type=refresh_token with client_id, client_secret and refresh_token; Get_Zoho_token keeps it 55 min in
// Object_store_accessToken; unauthorized-error-retrySub_Flow refreshes it on a 401) and called Zoho with
// "Zoho-oauthtoken <token>" for the contact search and the photo read/upload. Here every Zoho call goes
// through zoho-sys-api with the CRM path in the zohoPath header: zoho-sys-api holds the Zoho account, gets and
// refreshes the token and repeats on a 401, so this service never holds Zoho credentials.
// ---------------------------------------------------------------------------------------------

// object-store: zohoAccessToken -> zoho-sys-api (it signs in to Zoho and keeps the token in Redis; this service
// holds no Zoho account, so the old Get_Zoho_token / store_zoho_token flows have nothing to keep here)
isolated function zohoExchange(string method, string zohoPath, map<string[]> query, json body, string correlationId,
        boolean repeat = true) returns Reply|Stop {
    Reply reply = check send(ZOHO, zohoClient, method, core:withQuery(zohoSystemPath + "/Contacts", query), body,
            {"zohoPath": zohoPath}, correlationId, repeat, method == http:GET ? "crm read" : "crm write");
    // Zoho answers 204 without a body when nothing matches.
    return reply.status == 204 ? {status: 204, body: []} : reply;
}

isolated function zohoMessageOf(Reply reply) returns string {
    json target = core:fieldOf(reply.body, "targetError");
    foreach json candidate in [core:fieldOf(target, "message"),
        core:fieldOf(core:listOf(core:fieldOf(target, "data")).length() > 0 ? core:listOf(core:fieldOf(target, "data"))[0] : (),
                "message"), core:fieldOf(reply.body, "message")] {
        if core:has(candidate) {
            return core:textOf(candidate);
        }
    }
    return "Zoho answered " + reply.status.toString();
}

# A CRM write. An error answer of the CRM becomes `{status: "error", message}` (Mule: the
# requester's on-error-continue), which the callers report in their own answer.
#
# + method - POST or PUT
# + zohoPath - CRM path
# + body - Request body
# + correlationId - The request's correlation id
# + return - The CRM's answer
isolated function zohoWrite(string method, string zohoPath, json body, string correlationId) returns json|Stop {
    Reply reply = check zohoExchange(method, zohoPath, {}, body, correlationId);
    if reply.status >= 400 {
        return {"status": "error", "message": zohoMessageOf(reply)};
    }
    return reply.body;
}

# A CRM contact search.
#
# + criteria - Zoho search criteria
# + page - Page number; `()` for the first page with the CRM's page size
# + correlationId - The request's correlation id
# + return - The CRM's answer (`[]` when nothing matches)
isolated function zohoSearch(string criteria, int? page, string correlationId) returns json|Stop {
    map<string[]> query = {"criteria": [criteria]};
    if contactSearchFields.trim() != "" {
        query["fields"] = [contactSearchFields.trim()];
    }
    if page is int {
        query["page"] = [page.toString()];
        query["per_page"] = ["200"];
    }
    Reply reply = check zohoExchange(http:GET, contactSearchPath, query, (), correlationId);
    if reply.status >= 400 {
        return stopOf(reply.status, {"status": "error", "message": "Guest/Contact : " + zohoMessageOf(reply)});
    }
    return reply.body;
}

# A contact's picture as base64; `()` when it has none or it cannot be read.
#
# + contactId - CRM contact id
# + correlationId - The request's correlation id
# + return - The picture
isolated function zohoPhoto(string contactId, string correlationId) returns string? {
    map<string> headers = {"zohoPath": core:photoPathOf(contactPhotoPath, contactId)};
    headers[commons:CORRELATION_HEADER] = correlationId;
    http:Response|http:ClientError reply = zohoClient->get(zohoSystemPath + "/Contacts", headers);
    if reply is http:ClientError || reply.statusCode != 200 {
        return ();
    }
    byte[]|http:ClientError picture = reply.getBinaryPayload();
    return picture is byte[] && picture.length() > 0 ? picture.toBase64() : ();
}

# A contact's picture, from the photo cache when switched on: keyed by contact id and the contact's
# Modified_Time, so a changed contact is read fresh. A picture that could not be read is not kept.
#
# + contact - The contact (CRM search item)
# + correlationId - The request's correlation id
# + return - The picture as base64, `()` when it has none or it cannot be read
isolated function photoOf(json contact, string correlationId) returns string? {
    string contactId = core:textOf(core:fieldOf(contact, "id"));
    if !photoCache.enabled {
        return zohoPhoto(contactId, correlationId);
    }
    string key = "photo:" + contactId + "|" + core:textOf(core:fieldOf(contact, "Modified_Time"));
    string? kept = photoKept(key);
    if kept is string {
        return kept;
    }
    string? picture = zohoPhoto(contactId, correlationId);
    if picture is string {
        photoKeep(key, picture);
    }
    return picture;
}

isolated map<string> keptPhotos = {};

isolated function photoKept(string key) returns string? {
    if state.location() == "Redis" {
        string?|error got = state.get(key);
        return got is string ? got : ();
    }
    lock {
        return keptPhotos[key];
    }
}

isolated function photoKeep(string key, string picture) {
    if state.location() == "Redis" {
        error? failed = state.put(key, picture, photoCache.ttlSeconds);
        if failed is error {
            log:printWarn("Photo not kept", reason = failed.message());
        }
        return;
    }
    lock {
        if keptPhotos.length() >= photoCache.memoryEntries {
            keptPhotos.removeAll();
        }
        keptPhotos[key] = picture;
    }
}

# Uploads a contact's picture.
#
# + contactId - CRM contact id
# + picture - The picture as sent by the caller
# + correlationId - The request's correlation id
# + return - The CRM's answer
isolated function zohoPhotoUpload(string contactId, string picture, string correlationId) returns json|Stop =>
    zohoWrite(http:POST, core:photoPathOf(contactPhotoPath, contactId), {"file": core:plainBase64(picture)}, correlationId);

// ---------------------------------------------------------------------------------------------
// Guest id and loyalty id
// ---------------------------------------------------------------------------------------------

isolated function generatedId(string path, string name, string correlationId) returns string|Stop {
    Reply reply = check send(IDENTITY_SUPPORT, identitySupportClient, http:GET, path, (), {}, correlationId, true, name);
    string id = core:textOf(core:fieldOf(reply.body, name));
    if reply.status >= 400 || id == "" {
        return stopWith(commons:BAD_GATEWAY, "No " + name + " could be generated", correlationId);
    }
    return id;
}

isolated function generatedIds(string correlationId) returns [string, string]|Stop =>
    [check generatedId(generateGuestIdPath, "guestId", correlationId),
     check generatedId(generateLoyaltyIdPath, "loyaltyId", correlationId)];

// ---------------------------------------------------------------------------------------------
// Guest store (database system API)
// ---------------------------------------------------------------------------------------------

isolated function dbConfigured() returns boolean => isSet(DB);

# Runs one statement through the database system API.
#
# + body - The statement
# + step - What the statement is for, for the log
# + correlationId - The request's correlation id
# + return - The rows, or the answer when it failed
isolated function dbRun(map<json> body, string step, string correlationId) returns json|Stop {
    check requireSet(correlationId, DB);
    Reply reply = check send(DB, dbSysClient, http:POST, dbSystemPath, body, {}, correlationId, true, step);
    if reply.status >= 400 {
        log:printError("Guest store statement failed", correlationId = correlationId, step = step, status = reply.status);
        return stopOf(reply.status, reply.body is () ? core:plainErrorOf(commons:errorTypeOfStatus(reply.status),
                    "The guest store answered with an error: " + step) : reply.body);
    }
    return reply.body;
}

# A guest-store write that must not fail the operation (Mule: async / on-error-continue).
#
# + body - The statement
# + step - What the statement is for, for the log
# + correlationId - The request's correlation id
# + return - The rows; `()` when it was skipped or failed
isolated function dbBestEffort(map<json> body, string step, string correlationId) returns json {
    if !dbConfigured() {
        log:printWarn("Guest store write skipped: the backend address is not set: dbSystemApi.url",
                correlationId = correlationId, step = step);
        return ();
    }
    json|Stop rows = dbRun(body, step, correlationId);
    if rows is Stop {
        log:printWarn("Guest store write failed", correlationId = correlationId, step = step, status = rows.detail().status);
        return ();
    }
    return rows;
}

// ---------------------------------------------------------------------------------------------
// E-mail and CMS
// ---------------------------------------------------------------------------------------------

isolated function emailSend(map<json> message, string correlationId) returns Stop? {
    Reply reply = check send(EMAIL, emailClient, http:POST, emailNotificationPath, message, {"provider": emailProvider},
            correlationId, false, "e-mail");
    if reply.status >= 400 {
        log:printError("E-mail was not accepted", correlationId = correlationId, status = reply.status);
        return stopOf(reply.status, reply.body is () ? core:plainErrorOf(commons:errorTypeOfStatus(reply.status),
                    "The e-mail could not be sent") : reply.body);
    }
    if !core:handedOver(reply.status) {
        // Only an answer in the 200 range means the e-mail service took the message. A redirect
        // or any other answer means nothing was sent, so the caller must not be told "sent".
        log:printError("E-mail was not accepted", correlationId = correlationId, status = reply.status);
        return stopOf(502, core:plainErrorOf(commons:BAD_GATEWAY, "The e-mail could not be sent"));
    }
    return ();
}

isolated function cmsWelcome(map<string[]> query, string correlationId) returns json|Stop {
    Reply reply = check send(CMS, cmsClient, http:GET, core:withQuery(welcomeContentPath, query), (), {}, correlationId,
            false, "welcome content");
    if reply.status >= 400 {
        return stopOf(reply.status, reply.body is () ? core:plainErrorOf(commons:errorTypeOfStatus(reply.status),
                    "The welcome content could not be read") : reply.body);
    }
    return reply.body;
}

// ---------------------------------------------------------------------------------------------
// Seaware (through the reservation process API)
// ---------------------------------------------------------------------------------------------

isolated function seawareCall(string? token, map<json> body, string step, string correlationId) returns json|Stop {
    map<string> headers = {};
    if token is string {
        headers["Authorization"] = core:bearerOf(token);
    }
    Reply reply = check send(RESERVATION, reservationClient, http:POST, reservationTasksPath, body, headers,
            correlationId, false, step);
    if reply.status >= 400 {
        log:printError("Seaware call failed", correlationId = correlationId, step = step, status = reply.status);
        return stopOf(reply.status, reply.body is () ? core:plainErrorOf(commons:errorTypeOfStatus(reply.status),
                    "Seaware answered with an error: " + step) : reply.body);
    }
    return reply.body;
}

isolated function seawareLogin(string correlationId) returns string|Stop {
    check requireAgent(correlationId);
    json answer = check seawareCall((), core:loginRequestOf(seawareAgent), "login", correlationId);
    string? token = core:loginTokenOf(answer);
    if token is () {
        return stopWith(commons:BAD_GATEWAY, "Seaware did not open a session", correlationId);
    }
    return token;
}

isolated function seawareLogout(string token, string correlationId) {
    json|Stop answer = seawareCall(token, core:logoutRequestOf(), "logout", correlationId);
    if answer is Stop {
        log:printWarn("Seaware session could not be closed", correlationId = correlationId);
    }
}

isolated function requireAgent(string correlationId) returns Stop? {
    if seawareAgent.userName.trim() == "" {
        return stopWith(commons:SERVICE_UNAVAILABLE, "The Seaware agent account is not set: seawareAgent.userName",
                correlationId);
    }
    return ();
}

# Sends a Seaware request in an open session. An answer that says the session is gone is sent once
# more in a new session (Mule: Seaware_Error_check); when that does not help the operation stops.
# Any other Seaware error comes back in the answer, as Mule passed it on.
#
# + token - Token of the open session
# + body - GraphQL request
# + step - What the request is for, for the log
# + correlationId - The request's correlation id
# + return - Seaware's answer
isolated function seawareIn(string token, map<json> body, string step, string correlationId) returns json|Stop {
    json answer = check seawareCall(token, body, step, correlationId);
    string? message = core:firstSeawareError(answer);
    if message is string && core:isSessionError(message) {
        log:printWarn("Seaware session was not usable, the request is sent again", correlationId = correlationId,
                step = step);
        string again = check seawareLogin(correlationId);
        json|Stop repeated = seawareCall(again, body, step, correlationId);
        future<()> _ = start seawareLogout(again, correlationId);
        answer = check repeated;
        message = core:firstSeawareError(answer);
        if message is string && core:isSessionError(message) {
            return stopOf(500, core:plainErrorOf("GUEST-IDENTITY:CUSTOM-EERROR", message));
        }
    }
    if message is string {
        log:printWarn("Seaware answered with an error", correlationId = correlationId, step = step);
    }
    return answer;
}

# Runs one Seaware request in a session of its own: sign in, send, sign out.
#
# + body - GraphQL request
# + step - What the request is for, for the log
# + correlationId - The request's correlation id
# + return - Seaware's answer
isolated function seawareRun(map<json> body, string step, string correlationId) returns json|Stop {
    string token = check seawareLogin(correlationId);
    json|Stop answer = seawareIn(token, body, step, correlationId);
    future<()> _ = start seawareLogout(token, correlationId);
    return answer;
}

// ---------------------------------------------------------------------------------------------
// Seaware sessions kept open for read requests
// ---------------------------------------------------------------------------------------------

# An open Seaware session.
#
# + token - Its token
# + openedAt - Monotonic clock reading when it was opened
type SeawareSession readonly & record {|
    string token;
    decimal openedAt;
|};

// Sessions no request is using. A session is taken out for one request and put back after it, so
// two requests never share a session at the same moment.
isolated SeawareSession[] idleSessions = [];

isolated function sessionUsable(SeawareSession session) returns boolean =>
    time:monotonicNow() - session.openedAt < <decimal>seawareSessionMaxAgeSeconds;

# Takes the longest-kept usable session; the ones that are too old come back to be closed.
#
# + return - [a session or `()`, tokens of the sessions to close]
isolated function sessionTake() returns [SeawareSession?, readonly & string[]] {
    lock {
        string[] outdated = [];
        SeawareSession? found = ();
        while idleSessions.length() > 0 {
            SeawareSession candidate = idleSessions.shift();
            if sessionUsable(candidate) {
                found = candidate;
                break;
            }
            outdated.push(candidate.token);
        }
        return [found, outdated.cloneReadOnly()];
    }
}

# + session - A session no request is using any more
# + return - True when it was kept; false when the caller has to close it
isolated function sessionKeep(SeawareSession session) returns boolean {
    if !sessionUsable(session) {
        return false;
    }
    lock {
        if idleSessions.length() >= seawareSessionPoolSize {
            return false;
        }
        idleSessions.push(session);
        return true;
    }
}

# A session for one request: a kept usable one, else a new one (too-old kept ones are closed).
#
# + correlationId - The request's correlation id
# + return - The session
isolated function sessionAcquire(string correlationId) returns SeawareSession|Stop {
    if seawareSessionPoolSize <= 0 {
        return sessionOpen(correlationId);
    }
    [SeawareSession?, readonly & string[]] [kept, outdated] = sessionTake();
    foreach string token in outdated {
        future<()> _ = start seawareLogout(token, correlationId);
    }
    return kept ?: sessionOpen(correlationId);
}

isolated function sessionOpen(string correlationId) returns SeawareSession|Stop =>
    {token: check seawareLogin(correlationId), openedAt: time:monotonicNow()};

isolated function sessionsDrain() returns readonly & string[] {
    lock {
        string[] tokens = [];
        while idleSessions.length() > 0 {
            tokens.push(idleSessions.shift().token);
        }
        return tokens.cloneReadOnly();
    }
}

# Closes the kept sessions when the service stops.
#
# + return - Never an error
isolated function closeKeptSessions() returns error? {
    foreach string token in sessionsDrain() {
        seawareLogout(token, "shutdown");
    }
    return ();
}

# Runs one Seaware read request. The session is taken from the kept ones (a new one when none is
# free) and kept for the next read, so a read costs one Seaware request instead of three. A
# session Seaware no longer knows is replaced and the request sent once more, as `seawareIn` does.
# Requests that write keep using `seawareRun`: a session of their own, closed afterwards.
#
# + body - GraphQL request
# + step - What the request is for, for the log
# + correlationId - The request's correlation id
# + return - Seaware's answer
isolated function seawareRead(map<json> body, string step, string correlationId) returns json|Stop {
    if seawareSessionPoolSize <= 0 {
        return seawareRun(body, step, correlationId);
    }
    [SeawareSession?, readonly & string[]] [kept, outdated] = sessionTake();
    foreach string token in outdated {
        future<()> _ = start seawareLogout(token, correlationId);
    }
    SeawareSession session = kept ?: check sessionOpen(correlationId);
    json|Stop answer = seawareCall(session.token, body, step, correlationId);
    string? message = answer is Stop ? () : core:firstSeawareError(answer);
    if message is string && core:isSessionError(message) {
        log:printWarn("Seaware session was not usable, the request is sent again", correlationId = correlationId,
                step = step);
        future<()> _ = start seawareLogout(session.token, correlationId);
        session = check sessionOpen(correlationId);
        answer = seawareCall(session.token, body, step, correlationId);
        message = answer is Stop ? () : core:firstSeawareError(answer);
        if message is string && core:isSessionError(message) {
            future<()> _ = start seawareLogout(session.token, correlationId);
            return stopOf(500, core:plainErrorOf("GUEST-IDENTITY:CUSTOM-EERROR", message));
        }
    }
    if answer is Stop || !sessionKeep(session) {
        // A session whose request failed is not used again.
        future<()> _ = start seawareLogout(session.token, correlationId);
    }
    if message is string {
        log:printWarn("Seaware answered with an error", correlationId = correlationId, step = step);
    }
    return answer;
}

// ---------------------------------------------------------------------------------------------
// Reservations of a guest, kept for a short time (off unless tripsCacheSeconds is set)
// ---------------------------------------------------------------------------------------------

const MAX_KEPT_TRIPS = 500;

# Seaware's answer to a reservations query.
#
# + answer - The answer
# + at - Monotonic clock reading when it was read
type KeptTrips readonly & record {|
    json answer;
    decimal at;
|};

isolated map<KeptTrips> keptTrips = {};

isolated function tripsKept(string clientId) returns KeptTrips? {
    if tripsCacheSeconds <= 0 {
        return ();
    }
    lock {
        KeptTrips? kept = keptTrips[clientId];
        return kept is KeptTrips && time:monotonicNow() - kept.at < <decimal>tripsCacheSeconds ? kept : ();
    }
}

isolated function tripsKeep(string clientId, json answer) {
    if tripsCacheSeconds <= 0 {
        return;
    }
    KeptTrips entry = {answer: answer.cloneReadOnly(), at: time:monotonicNow()};
    lock {
        if keptTrips.length() >= MAX_KEPT_TRIPS {
            keptTrips.removeAll();
        }
        keptTrips[clientId] = entry;
    }
}

isolated function tripsForget(string clientId) {
    lock {
        if keptTrips.hasKey(clientId) {
            _ = keptTrips.remove(clientId);
        }
    }
}

// ---------------------------------------------------------------------------------------------
// Guest-store and CRM reads that run at the same time
// ---------------------------------------------------------------------------------------------

# The result of a guest-store statement that was started earlier.
#
# + pending - The running statement
# + step - What the statement is for, for the log
# + correlationId - The request's correlation id
# + return - The rows, or the answer when it failed
isolated function idSettled(future<string|Stop> pending, string name, string correlationId) returns string|Stop {
    string|Stop|error result = wait pending;
    if result is string || result is Stop {
        return result;
    }
    return stopWith(commons:BAD_GATEWAY, "No " + name + " could be generated", correlationId);
}

isolated function cmsSettled(future<json|Stop> pending, string correlationId) returns json|Stop {
    json|Stop|error result = wait pending;
    if result is json || result is Stop {
        return result;
    }
    return stopWith(commons:BAD_GATEWAY, "The welcome text could not be read", correlationId);
}

isolated function tokenSettled(future<string|Stop> pending, string correlationId) returns string|Stop {
    string|Stop|error result = wait pending;
    if result is string || result is Stop {
        return result;
    }
    return stopWith(commons:BAD_GATEWAY, "Seaware did not open a session", correlationId);
}

isolated function settled(future<json|Stop> pending, string step, string correlationId) returns json|Stop {
    json|error result = wait pending;
    if result is Stop {
        return result;
    }
    if result is error {
        log:printError("Guest store statement did not finish", correlationId = correlationId, step = step);
        return stopWith(commons:INTERNAL_SERVER_ERROR, "The guest store call did not finish: " + step, correlationId);
    }
    return result;
}

# + pending - The running CRM search
# + correlationId - The request's correlation id
# + return - True when the CRM knows the guest, or the answer when the search failed
isolated function crmSettled(future<boolean|Stop> pending, string correlationId) returns boolean|Stop {
    boolean|error result = wait pending;
    if result is Stop {
        return result;
    }
    if result is error {
        log:printError("CRM search did not finish", correlationId = correlationId);
        return stopWith(commons:INTERNAL_SERVER_ERROR, "The CRM search did not finish", correlationId);
    }
    return result;
}

# Hands an e-mail over without the caller waiting for it.
#
# + message - The e-mail request
# + correlationId - The request's correlation id
isolated function emailLater(map<json> & readonly message, string correlationId) {
    Stop? failed = emailSend(message, correlationId);
    if failed is Stop {
        log:printError("E-mail was not handed over after the answer", correlationId = correlationId,
                status = failed.detail().status);
    }
}
