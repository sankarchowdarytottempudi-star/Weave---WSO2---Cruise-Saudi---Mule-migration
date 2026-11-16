import identity_support_exp_api.core;

import ballerina/http;
import ballerina/log;
import ballerinax/prometheus as _;
import aroya/integration_commons as commons;

// identity-support-exp-api ("Guest Login"), ported by hand from the Mule application.
//
//   POST /otp/generate              -> Guest Identity POST /otp/generate
//   POST /otp/verify                -> Guest Identity POST /otp/verify
//   POST /processGuestIdentity      -> Guest Identity POST /processGuestIdentity
//   POST /guest-profiles            -> Guest Identity POST /guest-profiles
//   POST /guest-profiles/{guestId}  -> Guest Identity POST /guest-profiles/{guestId}
//   PUT  /guest-profiles/{guestId}  -> Guest Identity PUT  /guest-profiles/{guestId}
//   GET  /getGuestId, /generateGuestId      -> a new guest id, made here
//   GET  /getLoyaltId, /generateLoyaltId    -> a new loyalty id, made here
//
// Kept from Mule: a successful answer is 200 whatever the process API's success status was, and
// a call to the process API is never repeated (a repeat would send a second one-time code).
// Different from Mule on purpose: audit and error records went to Kafka and an error e-mail was
// sent; here they are log lines. The error-mapping look-up needs the database system API; while
// that has no address, or does not answer, the process API's error is answered unchanged
// (Mule answered its default 500 when the look-up failed).

listener http:Listener httpListener = new (httpPort, timeout = 240);

final http:Client guestIdentityClient = check commons:newDownstreamClient(guestIdentityProcApi);
final http:Client dbSysClient = check commons:newDownstreamClient(dbSystemApi);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    string[] notSet = [];
    if core:isPlaceholderAddress(guestIdentityProcApi.url) {
        notSet.push("guestIdentityProcApi");
    }
    if !dbConfigured() {
        notSet.push("dbSystemApi");
    }
    log:printInfo("identity-support-exp-api starting", env = env, basePath = basePath, addressesNotSet = notSet,
            errorMappingCacheSeconds = errorMappingCacheSeconds, warmUpAtStart = warmUpAtStart);
    log:printInfo("Error mappings kept in", place = state.location(), freshSeconds = errorMappingCacheSeconds,
            staleSeconds = errorMappingStaleSeconds, prefetch = errorMappingPrefetch);
    future<()> _ = start prefetchMappings();
    if warmUpAtStart {
        future<()> _ = start warmUp();
    } else {
        warmUpDone();
    }
}

final http:Service apiService = isolated service object {

    isolated resource function post otp/generate(http:Request request) returns http:Response {
        string correlationId = commons:correlationIdOf(request);
        map<string> headers = core:otpGenerateHeaders(
                commons:headerOf(request, "client_deviceid") ?: commons:headerOf(request, "client_device_id"),
                commons:headerOf(request, "client-ip"), commons:headerOf(request, "source-system"),
                commons:headerOf(request, "client_channel"));
        return forward("POST", "/otp/generate", {}, request, headers, correlationId);
    }

    isolated resource function post otp/verify(http:Request request) returns http:Response {
        string correlationId = commons:correlationIdOf(request);
        map<string[]> query = core:presentQuery({
            "site": request.getQueryParamValue("client_channel"),
            "locale": request.getQueryParamValue("client_locale")
        });
        return forward("POST", "/otp/verify", query, request, {}, correlationId);
    }

    isolated resource function post processGuestIdentity(http:Request request) returns http:Response {
        string correlationId = commons:correlationIdOf(request);
        map<string> headers = core:presentHeaders({
            "client_channel": commons:headerOf(request, "client_channel"),
            "client_realTime": commons:headerOf(request, "client_realTime"),
            "client_device_id": commons:headerOf(request, "client_device_id"),
            "client_authorization": commons:headerOf(request, "client_authorization")
        });
        return forward("POST", "/processGuestIdentity", {}, request, headers, correlationId);
    }

    isolated resource function post guest\-profiles(http:Request request) returns http:Response {
        string correlationId = commons:correlationIdOf(request);
        map<string> headers = core:presentHeaders({"source-system": commons:headerOf(request, "source-system")});
        map<string[]> query = core:presentQuery({
            "perPage": request.getQueryParamValue("perPage"),
            "page": request.getQueryParamValue("page")
        });
        return forward("POST", "/guest-profiles", query, request, headers, correlationId);
    }

    isolated resource function post guest\-profiles/[string guestId](http:Request request) returns http:Response {
        string correlationId = commons:correlationIdOf(request);
        map<string> headers = core:presentHeaders({
            "source-system": commons:headerOf(request, "source-system"),
            "device_id": commons:headerOf(request, "client_deviceid") ?: commons:headerOf(request, "client_device_id")
                ?: commons:headerOf(request, "device_id")
        });
        return forward("POST", "/guest-profiles/" + core:pathSegment(guestId), {}, request, headers, correlationId);
    }

    isolated resource function put guest\-profiles/[string guestId](http:Request request) returns http:Response {
        string correlationId = commons:correlationIdOf(request);
        map<string> headers = core:presentHeaders({"source-system": commons:headerOf(request, "source-system")});
        return forward("PUT", "/guest-profiles/" + core:pathSegment(guestId), {}, request, headers, correlationId);
    }

    isolated resource function get getGuestId(http:Request request) returns http:Response =>
        newGuestId(commons:correlationIdOf(request));

    isolated resource function get generateGuestId(http:Request request) returns http:Response =>
        newGuestId(commons:correlationIdOf(request));

    isolated resource function get getLoyaltId(http:Request request) returns http:Response =>
        newLoyaltyId(commons:correlationIdOf(request));

    isolated resource function get generateLoyaltId(http:Request request) returns http:Response =>
        newLoyaltyId(commons:correlationIdOf(request));
};

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    // "Ready" comes after the warm-up, so a new version takes over only when it answers fast.
    isolated resource function get ready() returns http:Response {
        boolean up = isReady();
        http:Response response = new;
        response.statusCode = up ? 200 : 503;
        response.setJsonPayload({status: up ? "UP" : "WARMING"});
        return response;
    }
}
