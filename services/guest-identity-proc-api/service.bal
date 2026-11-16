// guest-identity-proc-api (Guest Identity) - written by hand from the Mule application.
//
// Operations
//   GET  /processGuestBookingInfo   a guest's details from the CRM, by loyalty id and guest id
//   POST /processGuestIdentity      Seaware client + CRM contact (guest id, loyalty id) per guest
//   POST /otp/generate              one-time password by e-mail (sign-up also creates the guest)
//   POST /otp/verify                checks the password; a login gets a session token
//   POST /guest-profiles            the profiles of an e-mail address, a page at a time
//   POST /guest-profiles/{guestId}  the guest's trips, family and friends
//   PUT  /guest-profiles/{guestId}  edits the profile in Seaware, the CRM and the guest store
//   POST /bookingLogin              links the caller's device to the guest
//
// Backends: Seaware through reservation-common-proc-api, Zoho CRM through zoho-sys-api, ids from
// identity-support-exp-api, the guest store through the database system API, e-mail through
// email-sys-api and the welcome content from the CMS. Where an address is not set the operations
// that need it answer 503 "The backend address is not set: <name>.url" before anything is written.
//
// Not ported: Kafka audit and error publishing and the error e-mail (log lines instead), the Mule
// gateway's client_id / client_secret headers, and the Zoho token handling (zoho-sys-api does it).
//
// Deliberately different from Mule
//   - POST /otp/verify stops on a missing, used, locked or expired password. Mule went on, and a
//     missing record ended as "verified".
//   - A guest without name, e-mail address and phone is not searched in Seaware (Mule searched
//     without criteria, which matches any client).
//   - Values that stand without quotes in a Seaware request keep letters, digits and _ only.
//   - The reads of an OTP request go to the guest store and the CRM at the same time (Mule: one
//     after the other); the results are looked at in Mule's order, so the answers are the same.
//   - Seaware reads reuse open sessions and the reservations query asks only for the fields the
//     answer uses (config.bal, "Speed").
//   - Calls that write are sent once; only Zoho, id generation and guest-store calls are repeated
//     when the backend cannot be reached.

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/time;
import aroya/integration_commons as commons;

listener http:Listener httpListener = new (httpPort, timeout = 240);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    log:printInfo("guest-identity-proc-api starting", env = env, basePath = basePath,
            deploymentTarget = deploymentTarget, addressesNotSet = addressesNotSet(),
            seawareAgentSet = seawareAgent.userName.trim() != "", sessionSigningKeySet = sessionSigningKey != "",
            seawareSessionPoolSize = seawareSessionPoolSize, tripsCacheSeconds = tripsCacheSeconds,
            otpEmailAfterAnswer = otpEmailAfterAnswer, warmUpAtStart = warmUpAtStart);
    runtime:onGracefulStop(closeKeptSessions);
    if warmUpAtStart {
        future<()> _ = start warmUp();
    } else {
        warmUpDone();
    }
}

final http:Service apiService = isolated service object {

    isolated resource function get processGuestBookingInfo(http:Request request) returns http:Response {
        decimal began = time:monotonicNow();
        string correlationId = commons:correlationIdOf(request);
        return answered(bookingInfo(request, correlationId), "GET /processGuestBookingInfo", correlationId, began);
    }

    isolated resource function post processGuestIdentity(http:Request request) returns http:Response {
        decimal began = time:monotonicNow();
        string correlationId = commons:correlationIdOf(request);
        return answered(processGuestIdentity(request, correlationId), "POST /processGuestIdentity", correlationId, began);
    }

    isolated resource function post otp/generate(http:Request request) returns http:Response {
        decimal began = time:monotonicNow();
        string correlationId = commons:correlationIdOf(request);
        return answered(otpGenerate(request, correlationId), "POST /otp/generate", correlationId, began);
    }

    isolated resource function post otp/verify(http:Request request) returns http:Response {
        decimal began = time:monotonicNow();
        string correlationId = commons:correlationIdOf(request);
        return answered(otpVerify(request, correlationId), "POST /otp/verify", correlationId, began);
    }

    isolated resource function post guest\-profiles(http:Request request) returns http:Response {
        decimal began = time:monotonicNow();
        string correlationId = commons:correlationIdOf(request);
        return answered(profileList(request, correlationId), "POST /guest-profiles", correlationId, began);
    }

    isolated resource function post guest\-profiles/[string guestId](http:Request request) returns http:Response {
        decimal began = time:monotonicNow();
        string correlationId = commons:correlationIdOf(request);
        return answered(trips(request, guestId, correlationId), "POST /guest-profiles/{guestId}", correlationId, began);
    }

    isolated resource function put guest\-profiles/[string guestId](http:Request request) returns http:Response {
        decimal began = time:monotonicNow();
        string correlationId = commons:correlationIdOf(request);
        return answered(editProfile(request, guestId, correlationId), "PUT /guest-profiles/{guestId}", correlationId, began);
    }

    isolated resource function post bookingLogin(http:Request request) returns http:Response {
        decimal began = time:monotonicNow();
        string correlationId = commons:correlationIdOf(request);
        return answered(bookingLogin(request, correlationId), "POST /bookingLogin", correlationId, began);
    }
};

service /health on httpListener {
    resource function get live() returns json => {status: "UP"};

    // "Ready" comes after the warm-up, so a new version takes over only when it answers fast.
    resource function get ready() returns http:Response {
        boolean up = isReady();
        http:Response response = new;
        response.statusCode = up ? 200 : 503;
        response.setJsonPayload({status: up ? "UP" : "WARMING"});
        return response;
    }
}
