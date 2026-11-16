// POST /otp/generate and POST /otp/verify.

import guest_identity_proc_api.core;

import ballerina/http;
import ballerina/time;
import ballerina/uuid;
import aroya/integration_commons as commons;

isolated function lockStop(int retryAfterSeconds) returns Stop =>
    stopOf(429, core:lockedAnswerOf(retryAfterSeconds), {"Retry-After": retryAfterSeconds.toString()});

isolated function crmKnows(string criteria, string correlationId) returns boolean|Stop {
    json found = check zohoSearch(criteria, (), correlationId);
    return core:listOf(core:fieldOf(found, "data")).length() > 0;
}

isolated function otpGenerate(http:Request request, string correlationId) returns http:Response|Stop {
    json|http:ClientError sent = request.getJsonPayload();
    map<json>? payload = sent is http:ClientError ? () : core:requestFieldsOf(sent);
    if payload is () || core:trimmed(payload["identifier"]) == "" {
        return stopWith(commons:BAD_REQUEST, "identifier is required", correlationId);
    }
    string? sourceSystem = commons:headerOf(request, "source-system");
    string? sourcesystem = commons:headerOf(request, "sourcesystem");
    string? deviceId = commons:headerOf(request, "device_id");
    map<json> normalized = core:generateRequestOf(payload, deviceId, commons:headerOf(request, "client-ip"),
            sourcesystem ?: sourceSystem ?: "unknown");
    string identifier = core:textOf(normalized["identifier"]);
    string context = core:textOf(normalized["context"]);
    IdentityContext & readonly ctx = {
        channel: commons:headerOf(request, "client_channel") ?: sourceSystem ?: sourcesystem ?: "unknown",
        deviceId,
        realTime: false,
        correlationId
    };

    // Everything this request will need is checked before the first write.
    check requireSet(correlationId, DB, EMAIL);
    if context == "signup" {
        check requireIdentityBackends(ctx.channel, correlationId);
    } else if context == "login" {
        check requireSet(correlationId, ZOHO);
    }

    // The reads that do not depend on each other are sent at the same time. Their results are
    // looked at in the order Mule ran them, so every answer is the one it was before.
    string criteria = core:loginCriteriaOf(request.getQueryParamValue("criteria"), identifier);
    future<json|Stop> lockRead = start dbRun(core:lockCheckOf(identifier).cloneReadOnly(), "lock check", correlationId);
    future<json|Stop> userRead = start dbRun(core:otpUserOf(identifier).cloneReadOnly(), "registered check",
            correlationId);
    future<json|Stop> limitRead = start dbRun(core:rateLimitOf(identifier).cloneReadOnly(), "rate limit", correlationId);
    future<json|Stop>? guestRead = ();
    future<boolean|Stop>? crmRead = ();
    if context != "signup" {
        // A sign-up creates the guest first, so its look-up has to wait for that.
        guestRead = start dbRun(core:guestCoreOf(core:textOf(normalized["globalguestId"])).cloneReadOnly(),
                "guest lookup", correlationId);
    }
    if context == "login" {
        crmRead = start crmKnows(criteria, correlationId);
    }

    int retryAfter = core:retryAfterOf(check settled(lockRead, "lock check", correlationId));
    if retryAfter > 0 {
        return lockStop(retryAfter);
    }
    json[] registered = core:rowsOf(check settled(userRead, "registered check", correlationId));
    if context == "signup" {
        if registered.length() > 0 {
            return stopOf(core:RAISED_STATUS, core:alreadyRegistered());
        }
        json guest = check identityItem(core:signupGuestOf(normalized["metadata"], identifier).cloneReadOnly(), ctx);
        if core:textOf(core:fieldOf(guest, "status")).toLowerAscii() == "error" {
            json message = core:fieldOf(guest, "errorMessage");
            return stopOf(400, {
                "code": "SIGNUP_FAILED",
                "message": core:has(message) ? message
                    : (core:has(core:fieldOf(guest, "message")) ? core:fieldOf(guest, "message")
                        : "The guest could not be created")
            });
        }
    } else if context == "login" {
        if registered.length() == 0 || crmRead is () || !check crmSettled(crmRead, correlationId) {
            return stopOf(core:RAISED_STATUS, core:notRegistered());
        }
    }
    if core:rateLimited(check settled(limitRead, "rate limit", correlationId)) {
        return stopOf(429, core:rateLimitAnswer());
    }

    string code = core:otpCodeOf(uuid:createType4AsString());
    string salt = uuid:createType4AsString();
    time:Utc expiresAt = time:utcAddSeconds(time:utcNow(), <decimal>core:OTP_SECONDS);
    map<json>? guestCore = core:firstRowOf(guestRead is () ? check dbRun(core:guestCoreOf(
                            core:textOf(normalized["globalguestId"])), "guest lookup", correlationId)
            : check settled(guestRead, "guest lookup", correlationId));
    _ = check dbRun(core:otpInsertOf(normalized, core:safeRequestId(normalized["requestId"], uuid:createType4AsString()),
                    core:otpHashOf(code, salt), salt, expiresAt, guestCore is () ? () : guestCore["id"]),
            "password insert", correlationId);
    map<json> & readonly message = core:otpEmailOf(identifier, code, expiresAt, emailLogoUrl).cloneReadOnly();
    if otpEmailAfterAnswer {
        future<()> _ = start emailLater(message, correlationId);
    } else {
        check emailSend(message, correlationId);
    }
    return jsonAnswer(202, core:generateAnswerOf(normalized["requestId"], identifier), correlationId);
}

isolated function otpVerify(http:Request request, string correlationId) returns http:Response|Stop {
    json|http:ClientError sent = request.getJsonPayload();
    map<json>? payload = sent is http:ClientError ? () : core:requestFieldsOf(sent);
    if payload is () || core:trimmed(payload["identifier"]) == "" || core:trimmed(payload["otpCode"]) == "" {
        return stopWith(commons:BAD_REQUEST, "identifier and otpCode are required", correlationId);
    }
    map<json> verify = core:verifyRequestOf(payload);
    string identifier = core:textOf(verify["identifier"]);
    string context = core:textOf(verify["context"]);
    boolean login = context == "login";

    if login {
        check requireSet(correlationId, DB, ZOHO);
        if sessionSigningKey == "" {
            return stopWith(commons:SERVICE_UNAVAILABLE, "The session signing key is not set: sessionSigningKey",
                    correlationId);
        }
    } else {
        check requireSet(correlationId, DB, CMS, EMAIL);
    }

    // As in otpGenerate: the reads go out together and are looked at in Mule's order.
    string criteria = core:loginCriteriaOf(request.getQueryParamValue("criteria"), identifier);
    future<json|Stop> lockRead = start dbRun(core:lockCheckOf(identifier).cloneReadOnly(), "lock check", correlationId);
    future<json|Stop> userRead = start dbRun(core:otpUserOf(identifier, true).cloneReadOnly(), "registered check",
            correlationId);
    future<json|Stop> storedRead = start dbRun(core:otpLookupOf(verify).cloneReadOnly(), "password lookup",
            correlationId);
    future<boolean|Stop>? crmRead = ();
    if login {
        crmRead = start crmKnows(criteria, correlationId);
    }

    int retryAfter = core:retryAfterOf(check settled(lockRead, "lock check", correlationId));
    if retryAfter > 0 {
        return lockStop(retryAfter);
    }
    json registered = check settled(userRead, "registered check", correlationId);
    if login && (core:rowsOf(registered).length() == 0 || crmRead is () || !check crmSettled(crmRead, correlationId)) {
        return stopOf(core:RAISED_STATUS, core:notRegistered());
    }

    map<json>? stored = core:firstRowOf(check settled(storedRead, "password lookup", correlationId));
    core:OtpCheck verdict = core:otpCheckOf(stored, time:utcNow(), otpLockMinutes);
    map<string> retryHeader = {"Retry-After": (otpLockMinutes * 60).toString()};
    // Mule went on after these answers (a missing record even counted as verified); here they end the attempt.
    if stored is () || verdict.outcome != "compare" {
        if stored !is () && verdict.outcome == "expired" {
            _ = check dbRun(core:markExpiredOf(stored), "mark expired", correlationId);
        }
        return stopOf(verdict.status, verdict.body, verdict.outcome == "locked" ? retryHeader : {});
    }
    if !core:otpMatches(stored, core:textOf(verify["otpCode"])) {
        _ = check dbRun(core:failedAttemptOf(stored, otpLockMinutes), "count wrong code", correlationId);
        map<json>? state = core:firstRowOf(check dbRun(core:attemptStateOf(stored), "attempts", correlationId));
        [int, map<json>] [status, body] = core:wrongCodeAnswerOf(state, otpLockMinutes);
        return stopOf(status, body, status == 429 ? retryHeader : {});
    }

    if login {
        // Both writes of a verified login go out together; each one still has to succeed.
        future<json|Stop> usedWrite = start dbRun(core:markUsedOf(stored).cloneReadOnly(), "mark used", correlationId);
        future<json|Stop> verifiedWrite = start dbRun(core:guestVerifiedOf(stored).cloneReadOnly(), "guest verified",
                correlationId);
        _ = check settled(usedWrite, "mark used", correlationId);
        _ = check settled(verifiedWrite, "guest verified", correlationId);
        string|error token = core:accessTokenOf(identifier, sessionSigningKey, time:utcNow()[0]);
        if token is error {
            return stopWith(commons:INTERNAL_SERVER_ERROR, "The access token could not be signed", correlationId);
        }
        return jsonAnswer(200, core:verifiedAnswerOf(context, token, uuid:createType4AsString()), correlationId);
    }
    // Performance: the welcome text is read while the code is marked used; the mark is still looked
    // at first, so a failed write stops the request as before.
    future<json|Stop> cmsRead = start cmsWelcome(request.getQueryParams().cloneReadOnly(), correlationId);
    _ = check dbRun(core:markUsedOf(stored), "mark used", correlationId);
    json cms = check cmsSettled(cmsRead, correlationId);
    map<json>? firstUser = core:firstRowOf(registered);
    check emailSend(core:welcomeEmailOf(identifier, firstUser is () ? () : firstUser["metadata"], cms, emailLogoUrl,
                    appHomeUrl), correlationId);
    return jsonAnswer(200, core:verifiedAnswerOf(context), correlationId);
}
