// One-time passwords (Mule: genarate-otp-email-subflow, verify-otp-email-subflow, db-verify-implementation).

import ballerina/crypto;
import ballerina/time;

# Seconds a one-time password stays valid.
public const OTP_SECONDS = 300;

const OTP_TABLE = "cs_guest_mgmt.cs_otp_store";
const BY_OTP_ID = " WHERE otp_id = CAST(:otpId AS uuid)";

# What the stored record says about a verification attempt.
#
# + outcome - "compare" (the code must be checked), "notFound", "used", "locked" or "expired"
# + status - HTTP status of the answer when the attempt stops here
# + body - The answer when the attempt stops here
public type OtpCheck record {|
    string outcome;
    int status = 200;
    map<json> body = {};
|};

# The request of POST /otp/generate in its normal form (Mule: normalizedRequest).
#
# + body - The caller's body
# + deviceId - Header device_id
# + clientIp - Header client-ip
# + sourceChannel - Header sourcesystem, else source-system, else "unknown"
# + return - Normalized request
public isolated function generateRequestOf(map<json> body, string? deviceId, string? clientIp, string sourceChannel)
        returns map<json> {
    string channel = textOf(body["channel"]);
    string identifier = trimmed(body["identifier"]);
    return {
        "requestId": body["requestId"],
        "identifier": channel == "email" ? identifier.toLowerAscii() : identifier,
        "channel": channel,
        "context": trimmed(body["context"]).toLowerAscii(),
        "globalguestId": textOf(body["globalguestId"]),
        "deviceId": deviceId,
        "ipAddress": clientIp,
        "sourceChannel": sourceChannel,
        "metadata": body["metadata"]
    };
}

# The request of POST /otp/verify in its normal form (Mule: verifyRequest).
#
# + body - The caller's body
# + return - Normalized request
public isolated function verifyRequestOf(map<json> body) returns map<json> => {
    "requestId": body["requestId"],
    "identifier": trimmed(body["identifier"]).toLowerAscii(),
    "channel": body["channel"],
    "context": body["context"],
    "otpCode": trimmed(body["otpCode"])
};

# Seconds the identifier is still locked after too many wrong codes.
#
# + identifier - E-mail address or phone number
# + return - Request for the database system API
public isolated function lockCheckOf(string identifier) returns map<json> =>
    dbRequestOf("select", "SELECT COALESCE(CEIL(EXTRACT(EPOCH FROM (MAX(expires_at) - now()))), 0)::int AS retry_after FROM "
            + OTP_TABLE + " WHERE LOWER(identifier) = LOWER(:identifier) AND status = 'LOCKED' AND expires_at > now()",
            {"identifier": identifier});

# The seconds a lock-check answer reports.
#
# + answer - Database answer
# + return - Seconds, 0 when not locked
public isolated function retryAfterOf(json answer) returns int {
    map<json>? row = firstRowOf(answer);
    return row is () ? 0 : intOf(row["retry_after"], 0);
}

# The 429 answer of a locked identifier on POST /otp/generate.
#
# + retryAfterSeconds - Seconds until the lock ends
# + return - Answer body
public isolated function lockedAnswerOf(int retryAfterSeconds) returns map<json> => {
    "code": "OTP_LOCKED",
    "message": "Too many failed attempts. Try again in " + ((retryAfterSeconds + 59) / 60).toString() + " minutes.",
    "retryAfterSeconds": retryAfterSeconds
};

# The one-time-password records of an identifier: whoever has one has registered before.
#
# + identifier - E-mail address or phone number
# + withMetadata - True to read the stored sign-up details too
# + return - Request for the database system API
public isolated function otpUserOf(string identifier, boolean withMetadata = false) returns map<json> =>
    dbRequestOf("select", "SELECT otp_id, identifier, channel" + (withMetadata ? ", metadata" : "") + " FROM " + OTP_TABLE
            + " WHERE LOWER(identifier) = LOWER(:email)", {"email": identifier});

# The answer of the old application's error handler for an error a flow raises by name
# (Global_Error_Handler, the USER_NOT_REGISTERED and ALREADY_REGISTERED branches). The handler
# replaces the body and the status the flow had set just before raising: the caller always gets
# 400 with these fields, and the message is the description of the raised error.
#
# + errorType - Name of the raised error, without its "OTP:" namespace
# + description - Description of the raised error
# + return - Answer body
public isolated function raisedAnswerOf(string errorType, string description) returns map<json> => {
    "messageType": errorType,
    "message": description,
    "responseCode": RAISED_STATUS,
    "responsePayload": (),
    "errorDoesNotExist": false
};

# Status of every answer built by `raisedAnswerOf`.
public const int RAISED_STATUS = 400;

public isolated function alreadyRegistered() returns map<json> =>
    raisedAnswerOf("ALREADY_REGISTERED", "Account already exists. Please login.");

public isolated function notRegistered() returns map<json> =>
    raisedAnswerOf("USER_NOT_REGISTERED", "Please register before login");

# The CRM search that tells whether the identifier belongs to a contact.
#
# + criteria - Criteria the caller sent, if any
# + identifier - E-mail address
# + return - Zoho search criteria
public isolated function loginCriteriaOf(string? criteria, string identifier) returns string =>
    criteria is string && criteria.trim() != "" ? criteria : "((Email:equals:" + identifier + "))";

# The guest that a sign-up creates, from the details sent with the request.
#
# + metadata - `metadata` of the request
# + identifier - E-mail address
# + return - A guest in the shape of POST /processGuestIdentity
public isolated function signupGuestOf(json metadata, string identifier) returns map<json> {
    string gender = textOf(fieldOf(metadata, "gender")).toLowerAscii();
    map<json> guest = {
        "title": fieldOf(metadata, "title"),
        "firstName": fieldOf(metadata, "firstName"),
        "lastName": fieldOf(metadata, "lastName"),
        "firstNameNative": fieldOf(metadata, "firstNameNative"),
        "lastNameNative": fieldOf(metadata, "lastNameNative"),
        "gender": gender == "male" ? "M" : (gender == "female" ? "F" : ()),
        "email": identifier
    };
    foreach string name in ["nationalityKey", "nationalityName", "dateOfBirth", "countryOfResidenceKey",
        "countryOfResidenceName", "city", "languageKey", "languageName", "intlCode", "phone", "file",
        "identificationMethod"] {
        guest[name] = fieldOf(metadata, name);
    }
    return guest;
}

# Counts the passwords requested for the identifier in the last hour.
#
# + identifier - E-mail address or phone number
# + return - Request for the database system API
public isolated function rateLimitOf(string identifier) returns map<json> =>
    dbRequestOf("select", "SELECT count(*) AS cnt FROM " + OTP_TABLE
            + " WHERE identifier = :identifier AND created_at > now() - interval '1 hour'", {"identifier": identifier});

# True when more than five passwords were requested in the last hour.
#
# + answer - Database answer of the count
# + return - True when the limit is passed
public isolated function rateLimited(json answer) returns boolean {
    map<json>? row = firstRowOf(answer);
    return row !is () && intOf(row["cnt"], 0) > 5;
}

public isolated function rateLimitAnswer() returns map<json> => {"code": "RATE_LIMIT", "message": "Too many OTP requests. Please try again later."};

# The request id stored with the password: the caller's when it is a UUID, else a new one.
#
# + requestId - `requestId` of the request
# + fresh - A new UUID
# + return - The id to store
public isolated function safeRequestId(json requestId, string fresh) returns string {
    if requestId is string
        && re `[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}`.isFullMatch(requestId) {
        return requestId;
    }
    return fresh;
}

# A six-digit code that never starts with 0, taken from the random part of a version 4 UUID.
#
# + uuid - A random UUID
# + return - The code
public isolated function otpCodeOf(string uuid) returns string {
    string hex = re `-`.replaceAll(uuid, "");
    // The last twelve characters of a version 4 UUID are all random.
    int|error number = int:fromHexString(hex.length() >= 12 ? hex.substring(hex.length() - 12) : "0");
    return (100000 + (number is int ? number : 0) % 900000).toString();
}

# What is stored instead of the code: base64 of SHA-256 over code + salt.
#
# + code - The one-time password
# + salt - The record's salt
# + return - The hash
public isolated function otpHashOf(string code, string salt) returns string =>
    crypto:hashSha256((code + salt).toBytes()).toBase64();

isolated function two(int value) returns string => value < 10 ? "0" + value.toString() : value.toString();

# A moment as `yyyy-MM-dd HH:mm:ss` in UTC.
#
# + moment - The moment
# + return - Text
public isolated function stampOf(time:Utc moment) returns string {
    time:Civil c = time:utcToCivil(moment);
    decimal seconds = c.second ?: 0d;
    return c.year.toString() + "-" + two(c.month) + "-" + two(c.day) + " " + two(c.hour) + ":" + two(c.minute) + ":"
        + two(<int>seconds.floor());
}

# The guest-core row of a guest id.
#
# + globalGuestId - `globalguestId` of the request
# + return - Request for the database system API
public isolated function guestCoreOf(string globalGuestId) returns map<json> =>
    dbRequestOf("select", "SELECT id FROM cs_guest_mgmt.cs_guest_core WHERE global_guest_id = :gid",
            {"gid": globalGuestId});

# Stores a new one-time password.
#
# + request - Normalized request
# + requestId - Request id to store
# + otpHash - Hash of the code
# + salt - Salt of the hash
# + expiresAt - When the code stops being valid
# + guestCoreId - Id of the guest-core row, `()` when there is none
# + return - Request for the database system API
// Mule fields that never leave the old flows (checked against the uploaded jar):
//  - db-implementation-idempoentency-check builds {request_id, expires_in_seconds, masked_identifier, status}
//    when an ACTIVE row has the same request id, but genarate-otp-email-subflowSub_Flow never reads it: the
//    next step (db-implementation-check-guest-exists) replaces the payload and the flow goes on to insert and
//    e-mail as usual. The caller's answer is GenerateOtpResponse (generateAnswerOf below). Same here: no
//    short-cut on a repeated request id.
//  - db-implementation-insertotpDb: `format` is the DataWeave format of expiresAt
//    (`as String {format: "yyyy-MM-dd HH:mm:ss"}`), not a column; stampOf gives the same text (+00 = UTC).
//  - otpData.otpPlaintext only goes into the e-mail body (OTP-Email, the `otp` value) - as in otpEmailOf.
//    The "Messaging Payload" with an otpPlaintext field is replaced by the next transform and never sent.
//    Only otp_hash and salt are stored.
public isolated function otpInsertOf(map<json> request, string requestId, string otpHash, string salt,
        time:Utc expiresAt, json guestCoreId) returns map<json> {
    json metadata = request["metadata"];
    return dbRequestOf("insert", "INSERT INTO " + OTP_TABLE + " (identifier, device_id, channel, context, otp_hash, salt,"
            + " expires_at, attempts, max_attempts, status, request_id, ip_address, source_channel, metadata,"
            + " cs_guest_core_id) VALUES (:identifier, :deviceId, :channel, :context, :otpHash, :salt,"
            + " :expiresAt::timestamptz, 0, 3, 'ACTIVE', :requestId, :ipAddress, :sourceChannel, :metadata::jsonb, :gid)",
            {
                "identifier": request["identifier"],
                "deviceId": request["deviceId"],
                "channel": request["channel"],
                "context": request["context"],
                "otpHash": otpHash,
                "salt": salt,
                // "+00": the time is UTC whatever the database session's time zone is.
                "expiresAt": stampOf(expiresAt) + "+00",
                "requestId": requestId,
                "ipAddress": request["ipAddress"],
                "sourceChannel": request["sourceChannel"],
                "metadata": (metadata is () ? {} : metadata).toJsonString(),
                "gid": guestCoreId
            });
}

# The identifier as shown in the e-mail: the first three characters and stars.
#
# + identifier - E-mail address or phone number
# + return - Masked text
public isolated function maskedForMail(string identifier) returns string {
    int? at = identifier.indexOf("@");
    if at is int {
        string domain = identifier.substring(at + 1);
        return (at > 3 ? identifier.substring(0, 3) : "") + "***@" + domain;
    }
    int length = identifier.length();
    if length > 6 {
        string stars = "";
        foreach int i in 0 ..< length - 6 {
            stars += "*";
        }
        return identifier.substring(0, 3) + stars + identifier.substring(length - 3);
    }
    return identifier;
}

# The identifier as shown in the answer of POST /otp/generate.
#
# + identifier - E-mail address or phone number
# + return - Masked text
public isolated function maskedForAnswer(string identifier) returns string {
    int? at = identifier.indexOf("@");
    if at is int && identifier.length() > 7 {
        int end = int:min(identifier.length(), at + 5);
        return identifier.substring(0, int:min(3, at)) + "***@" + identifier.substring(at + 1, end);
    }
    return identifier;
}

# The e-mail that carries the one-time password.
#
# + identifier - Receiver
# + code - The one-time password
# + expiresAt - When the code stops being valid
# + logoUrl - Address of the logo picture
# + return - Message for the e-mail system API
public isolated function otpEmailOf(string identifier, string code, time:Utc expiresAt, string logoUrl) returns map<json> {
    string body = "<!DOCTYPE html><html><body style='margin:0;font-family:Arial;background:#f4f7fb;'>"
        + "<table width='100%' cellpadding='0' cellspacing='0' style='padding:20px;'><tr><td align='center'>"
        + "<table width='500' style='background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 4px 10px rgba(0,0,0,0.08);'>"
        + "<tr><td style='background:linear-gradient(90deg,#0b3d91,#00a8e8);color:#fff;padding:20px;text-align:center;'>"
        + "<img src='" + logoUrl + "' alt='Aroya Cruises' style='max-width:140px;height:auto;display:block;margin:0 auto 8px;'/>"
        + "<p style='margin:5px 0 0;font-size:13px;'>Welcome Aboard</p>"
        + "</td></tr>"
        + "<tr><td style='padding:30px;text-align:center;'>"
        + "<h3 style='margin:0;color:#333;'>Verify Your Account</h3>"
        + "<p style='color:#555;font-size:14px;margin-top:10px;'>Use the One-Time Password (OTP) below to complete your verification with Aroya.</p>"
        + "<div style='margin:30px 0;'>"
        + "<span style='display:inline-block;font-size:28px;letter-spacing:6px;font-weight:bold;color:#0b3d91;background:#f0f4ff;padding:12px 24px;border-radius:8px;'>"
        + code + "</span>"
        + "</div>"
        + "<p style='font-size:13px;color:#777;'>This OTP was sent to <strong>" + htmlText(maskedForMail(identifier))
        + "</strong> and is valid for <strong>5 minutes</strong>. Do not share it with anyone.</p>"
        + "<p style='font-size:12px;color:#aaa;margin-top:6px;'> Expires: " + stampOf(expiresAt) + "</p>"
        + "</td></tr>"
        + "<tr><td style='background:#f9fafc;padding:15px;text-align:center;font-size:12px;color:#999;'>"
        + "© Aroya Cruises • Saudi Arabia<br/>Experience the future of luxury cruising"
        + "</td></tr>"
        + "</table></td></tr></table></body></html>";
    return {"to": [identifier], "subject": "Aroya – Your OTP Code", "body": body};
}

# The 202 answer of POST /otp/generate.
#
# + requestId - `requestId` of the request, as sent
# + identifier - E-mail address or phone number
# + return - Answer body
public isolated function generateAnswerOf(json requestId, string identifier) returns map<json> => {
    "requestId": requestId,
    "expiresInSeconds": OTP_SECONDS,
    "maskedIdentifier": maskedForAnswer(identifier),
    "status": "ACTIVE"
};

// ---------------------------------------------------------------------------------------------
// Verify
// ---------------------------------------------------------------------------------------------

# The stored password a verification is about: by request id when one is sent, else the latest
# one of the identifier, channel and context.
#
# + request - Normalized request
# + return - Request for the database system API
public isolated function otpLookupOf(map<json> request) returns map<json> {
    if has(request["requestId"]) {
        return dbRequestOf("select", "SELECT * FROM " + OTP_TABLE + " WHERE request_id = :requestId AND status = 'ACTIVE' LIMIT 1",
                {"requestId": request["requestId"]});
    }
    return dbRequestOf("select", "SELECT * FROM " + OTP_TABLE + " WHERE identifier = :identifier AND channel = :channel"
            + " AND context = :context ORDER BY created_at DESC LIMIT 1",
            {"identifier": request["identifier"], "channel": request["channel"], "context": request["context"]});
}

# A database timestamp as a moment; `()` when it cannot be read.
#
# + value - Timestamp as the database system API returns it
# + return - The moment
public isolated function momentOf(json value) returns time:Utc? {
    string text = trimmed(value);
    if text == "" {
        return ();
    }
    text = re ` `.replace(text, "T");
    if text.length() > 10 {
        string clock = text.substring(10);
        if !clock.includes("Z") && !clock.includes("+") && !clock.includes("-") {
            text += "Z";
        } else if re `.*[+\-]\d\d`.isFullMatch(clock) {
            text += ":00";
        }
    }
    time:Utc|time:Error moment = time:utcFromString(text);
    return moment is time:Utc ? moment : ();
}

# Looks at the stored password before the code is compared (Mule: otpValidation).
#
# + row - The stored record, `()` when there is none
# + now - The current moment
# + lockMinutes - Minutes an identifier stays locked
# + return - Whether to compare the code, or the answer that ends the attempt
// Mule (verify-otp-email-subflow, Validation Logic): the error object's httpStatus is copied into the
// variable that becomes the HTTP status of the answer (`status` here); it is not a body field the caller gets.
public isolated function otpCheckOf(map<json>? row, time:Utc now, int lockMinutes) returns OtpCheck {
    if row is () {
        return {
            outcome: "notFound",
            status: 404,
            body: {"status": "ERROR", "code": "OTP_NOT_FOUND", "message": "No OTP record found."}
        };
    }
    string status = textOf(row["status"]);
    if status == "USED" {
        return {
            outcome: "used",
            status: 400,
            body: {"status": "ERROR", "code": "OTP_ALREADY_USED", "message": "This OTP has already been used."}
        };
    }
    if status == "LOCKED" || intOf(row["attempts"], 0) >= intOf(row["max_attempts"], 3) {
        return {
            outcome: "locked",
            status: 429,
            body: {
                "status": "ERROR",
                "code": "OTP_LOCKED",
                "message": "Too many failed attempts. Try again after " + lockMinutes.toString() + " minutes."
            }
        };
    }
    time:Utc? expires = momentOf(row["expires_at"]);
    if expires is () || time:utcDiffSeconds(now, expires) > 0d {
        return {
            outcome: "expired",
            status: 410,
            body: {"code": "OTP_EXPIRED", "message": "OTP has expired. Please request a new OTP", "remainingAttempts": 0}
        };
    }
    return {outcome: "compare"};
}

# True when the code the caller sent is the stored one.
#
# + row - The stored record
# + code - The code the caller sent
# + return - True on a match
public isolated function otpMatches(map<json> row, string code) returns boolean =>
    otpHashOf(code, textOf(row["salt"])) == textOf(row["otp_hash"]);

isolated function byOtpId(string operation, string statement, map<json> row, map<json> more = {}) returns map<json> {
    map<json> params = {"otpId": row["otp_id"]};
    foreach [string, json] [name, value] in more.entries() {
        params[name] = value;
    }
    return dbRequestOf(operation, statement, params);
}

public isolated function markExpiredOf(map<json> row) returns map<json> =>
    byOtpId("update", "UPDATE " + OTP_TABLE + " SET status = 'EXPIRED'" + BY_OTP_ID, row);

public isolated function markUsedOf(map<json> row) returns map<json> =>
    byOtpId("update", "UPDATE " + OTP_TABLE + " SET status = 'USED'" + BY_OTP_ID, row);

# Marks the guest of a login password as verified.
#
# + row - The stored record
# + return - Request for the database system API
public isolated function guestVerifiedOf(map<json> row) returns map<json> =>
    byOtpId("update", "UPDATE cs_guest_mgmt.cs_guest_core g SET status = 'verified' FROM " + OTP_TABLE
            + " o WHERE g.id = o.cs_guest_core_id AND o.otp_id = CAST(:otpId AS uuid)", row);

# Counts a wrong code; the record locks when the attempts are used up.
#
# + row - The stored record
# + lockMinutes - Minutes an identifier stays locked
# + return - Request for the database system API
public isolated function failedAttemptOf(map<json> row, int lockMinutes) returns map<json> =>
    byOtpId("update", "UPDATE " + OTP_TABLE + " SET attempts = attempts + 1,"
            + " status = CASE WHEN (attempts + 1) >= max_attempts THEN 'LOCKED' ELSE status END,"
            + " expires_at = CASE WHEN (attempts + 1) >= max_attempts THEN now() + make_interval(mins => CAST(:lockMinutes AS int))"
            + " ELSE expires_at END" + BY_OTP_ID + " AND status = 'ACTIVE' AND attempts < max_attempts", row,
            {"lockMinutes": lockMinutes});

public isolated function attemptStateOf(map<json> row) returns map<json> =>
    byOtpId("select", "SELECT attempts, max_attempts, status, created_at FROM " + OTP_TABLE + BY_OTP_ID, row);

# The answer to a wrong code.
#
# + state - The record's attempts after the wrong code was counted
# + lockMinutes - Minutes an identifier stays locked
# + return - [HTTP status, answer body]
public isolated function wrongCodeAnswerOf(map<json>? state, int lockMinutes) returns [int, map<json>] {
    if state !is () && textOf(state["status"]) == "LOCKED" {
        return [429, {
            "code": "OTP_LOCKED",
            "message": "Too many failed attempts. Try again after " + lockMinutes.toString() + " minutes.",
            "remainingAttempts": 0,
            "retryAfterSeconds": lockMinutes * 60
        }];
    }
    int remaining = state is () ? 0 : intOf(state["max_attempts"], 3) - intOf(state["attempts"], 0);
    return [409, {"code": "OTP_INVALID", "message": "Invalid OTP code", "remainingAttempts": int:max(remaining, 0)}];
}

isolated function urlSafe(byte[] data) returns string {
    string text = data.toBase64();
    text = re `\+`.replaceAll(text, "-");
    text = re `/`.replaceAll(text, "_");
    return re `=`.replaceAll(text, "");
}

# The access token of a verified login: a JWT signed with HMAC SHA-256 that is valid for an hour.
#
# + identifier - The verified identifier
# + signingKey - The signing key
# + issuedAt - Seconds since 1970
# + return - The token, or an error when it cannot be signed
public isolated function accessTokenOf(string identifier, string signingKey, int issuedAt) returns string|error {
    map<json> claims = {
        "sub": identifier == "" ? "anonymous" : identifier,
        "type": "access",
        "iat": issuedAt,
        "exp": issuedAt + 3600,
        "iss": "mule-otp-service"
    };
    string unsigned = urlSafe("{\"alg\":\"HS256\",\"typ\":\"JWT\"}".toBytes()) + "." + urlSafe(claims.toJsonString().toBytes());
    byte[] signature = check crypto:hmacSha256(unsigned.toBytes(), signingKey.toBytes());
    return unsigned + "." + urlSafe(signature);
}

# The answer of a verified one-time password.
#
# + context - Context of the request
# + accessToken - Access token of a login, `()` for other contexts
# + refreshToken - Refresh token of a login
# + return - Answer body
public isolated function verifiedAnswerOf(string context, string? accessToken = (), string refreshToken = "")
        returns map<json> {
    if accessToken is string {
        return {
            "success": true,
            "status": "VERIFIED",
            "context": "login",
            "message": "OTP verified successfully.",
            "session": {"accessToken": accessToken, "refreshToken": refreshToken, "tokenType": "Bearer", "expiresIn": 3600}
        };
    }
    return {
        "success": true,
        "status": "VERIFIED",
        "context": context,
        "message": context == "signup" ? "Account verified successfully." : "Login successful."
    };
}

isolated function firstOf(json value) returns json {
    json[] items = listOf(value);
    return items.length() > 0 ? items[0] : ();
}

isolated function textOr(json value, string fallback) returns string => has(value) ? textOf(value) : fallback;

# The welcome e-mail that follows a verified sign-up, built from the CMS welcome content.
#
# + identifier - Receiver
# + metadata - Sign-up details stored with the password (a JSON object, or its text)
# + cms - Answer of the CMS welcome content
# + defaultLogoUrl - Logo used when the content has no picture
# + defaultButtonUrl - Link used when the content has none
# + return - Message for the e-mail system API
public isolated function welcomeEmailOf(string identifier, json metadata, json cms, string defaultLogoUrl,
        string defaultButtonUrl) returns map<json> {
    json details = metadata is string ? jsonOfText(metadata) : metadata;
    string firstName = htmlText(textOr(fieldOf(details, "firstName"), "Guest"));
    json content = firstOf(fieldOf(cms, "data"));
    json component = firstOf(fieldOf(content, "components"));
    json media = firstOf(fieldOf(component, "media"));
    json cta = firstOf(fieldOf(component, "cta"));

    string logoUrl = textOr(fieldOf(media, "formats", "small", "url"), textOr(fieldOf(media, "url"), defaultLogoUrl));
    string logoAlt = textOr(fieldOf(media, "alternativeText"), textOr(fieldOf(media, "name"), "AROYA Cruises"));
    string description = re `\{\{name\}\}`.replaceAll(textOf(fieldOf(component, "description")), firstName);
    description = re `\n\s*\n`.replaceAll(description, "<br/><br/>");
    description = re `\n`.replaceAll(description, " ");
    string buttonText = textOr(fieldOf(cta, "text"), "Start Exploring");
    string buttonUrl = textOr(fieldOf(cta, "link_url"), defaultButtonUrl);
    string buttonBg = textOr(fieldOf(cta, "buttonColor"), "#0b3d91");
    string buttonTextColor = textOr(fieldOf(cta, "buttonTextColor"), "#ffffff");
    string pageTitle = textOr(fieldOf(content, "page_title"), "Welcome Aboard");
    string heroTitle = textOr(fieldOf(component, "title"), "Welcome Aboard");
    string subtitle = fieldOf(component, "has_subtitle") == true ? textOf(fieldOf(component, "subtitle")) : "";
    string footer1 = fieldOf(component, "has_description_1") == true ? trimmed(fieldOf(component, "description_1")) : "";
    string footer2 = fieldOf(component, "has_description_2") == true ? trimmed(fieldOf(component, "description_2")) : "";

    string body = "<!DOCTYPE html><html><body style='margin:0;padding:0;font-family:Arial,Helvetica,sans-serif;background:#f4f7fb;'>"
        + "<table width='100%' cellpadding='0' cellspacing='0' border='0' style='background:#f4f7fb;padding:20px;'><tr><td align='center'>"
        + "<table width='600' cellpadding='0' cellspacing='0' border='0' style='background:#ffffff;border-radius:12px;overflow:hidden;'>"
        + "<tr><td style='padding:25px 20px 5px 20px;text-align:center;background:#ffffff;'>"
        + "<img src='" + logoUrl + "' alt='" + logoAlt + "' style='max-width:160px;height:auto;display:block;margin:0 auto;'/></td></tr>"
        + "<tr><td style='padding:0 40px 10px 40px;text-align:center;background:#ffffff;color:#333333;'>"
        + "<h2 style='margin:0;font-size:24px;font-weight:bold;color:#333333;'>" + heroTitle + "</h2>"
        + (subtitle == "" ? "" : "<p style='margin:8px 0 0 0;font-size:14px;color:#666666;'>" + subtitle + "</p>")
        + "</td></tr>"
        + "<tr><td style='padding:15px 40px 20px 40px;text-align:center;color:#333333;'>"
        + "<div style='font-size:16px;line-height:28px;color:#555555;'>" + description + "</div>"
        + "<div style='margin-top:35px;'><a href='" + buttonUrl + "' target='_blank' style='background:" + buttonBg
        + ";color:" + buttonTextColor + ";text-decoration:none;padding:14px 30px;border-radius:8px;font-size:15px;"
        + "font-weight:bold;display:inline-block;'>" + buttonText + "</a></div></td></tr>"
        + "<tr><td style='padding:20px;text-align:center;background:#f9fafc;font-size:12px;color:#999999;line-height:20px;"
        + "border-top:1px solid #eeeeee;'>" + (footer1 == "" ? "" : footer1 + "<br/>") + footer2 + "</td></tr>"
        + "</table></td></tr></table></body></html>";
    return {"to": [identifier], "subject": pageTitle, "body": body};
}
