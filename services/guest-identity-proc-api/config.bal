import guest_identity_proc_api.core;

import aroya/integration_commons as commons;

configurable string env = ?;
configurable int httpPort = 8081;
configurable string basePath = "/guest-identity-proc-api/v1";

# "shore" or "ship" (Mule: deploymentTarget) - decides how POST /bookingLogin stores the guest.
configurable string deploymentTarget = "shore";

// Backends. An address that is not set stays on the placeholder; the operations that need it then
// answer 503 "The backend address is not set: <name>.url" before anything is written.

# Seaware, through the reservation process API's GraphQL pass-through.
configurable commons:DownstreamSettings reservationProcApi = {url: "http://localhost"};
configurable string reservationTasksPath = "/reservation-common-proc-api/v1/integration-tasks";

# Zoho CRM, through the Zoho system API (which also keeps the Zoho token).
configurable commons:DownstreamSettings zohoSysApi = {url: "http://localhost"};
configurable string zohoSystemPath = "/zoho-sys-api/v1/zoho";

# Guest id and loyalty id generation.
configurable commons:DownstreamSettings identitySupportExpApi = {url: "http://localhost"};
configurable string generateGuestIdPath = "/identity-support-exp-api/v1/generateGuestId";
configurable string generateLoyaltyIdPath = "/identity-support-exp-api/v1/generateLoyaltId";

# The guest store (one-time passwords, guest core, device links), through the database system API.
configurable commons:DownstreamSettings dbSystemApi = {url: "http://localhost"};
configurable string dbSystemPath = "/db-sys-api/v1/db";

# E-mail sending.
configurable commons:DownstreamSettings emailSysApi = {url: "http://localhost"};
configurable string emailNotificationPath = "/email-sys-api/v1/send-email-notification";
configurable string emailProvider = "exchange";

# CMS content of the welcome e-mail.
configurable commons:DownstreamSettings cmsContentApi = {url: "http://localhost"};
configurable string welcomeContentPath = "/cms-proc-api/v1/cms/content/welcome-aboard";

# The Seaware reservation agent this API signs in as.
configurable core:SeawareAgent seawareAgent = {};

# Key that signs the access token of a verified login. Not set -> login verification answers 503.
configurable string sessionSigningKey = "";

# Channels whose guests are also written to the CRM.
configurable string[] channelCheck = ["otalioBatch", "seawareBatch", "mobile", "web"];

# Minutes an identifier stays locked after too many wrong codes.
configurable int otpLockMinutes = 30;

# Repeats of a call whose backend could not be reached (Zoho, id generation, guest store).
configurable int httpRetryCount = 3;
configurable decimal httpRetryFrequencySeconds = 5;

# Guests of one POST /processGuestIdentity request that are processed at the same time.
configurable int identityParallelism = 4;

// Zoho CRM paths.
configurable string contactUpsertPath = "/crm/v6/Contacts/upsert";
configurable string contactUpdatePath = "/crm/v2/Contacts";
configurable string contactSearchPath = "/crm/v6/Contacts/search";
# Contact fields asked for in a CRM search (comma separated). Empty = every field, as the old
# application did. Must contain every field this service reads from a contact.
configurable string contactSearchFields = "";
configurable string contactPhotoPath = "/crm/v8/Contacts/{contactId}/photo";

# Logo of the e-mails, and the link of the welcome e-mail's button when the CMS has none.
configurable string emailLogoUrl = "";
configurable string appHomeUrl = "";

// Speed. None of these changes an answer, except where the comment says so.

# Seaware sessions kept open for read requests, so a read does not sign in and out each time.
# 0 = a session of its own for every request, as before.
configurable int seawareSessionPoolSize = 4;

# Seconds a kept Seaware session is used before it is closed.
configurable int seawareSessionMaxAgeSeconds = 600;

# Seconds one Seaware read session (the agent account's) is shared by every read request, in every
# copy of the service (through stateRedis), before a new one is opened. Seaware answers concurrent
# reads in one session (checked 2026-11-20: 10 parallel reads, no errors, no queueing). A session
# Seaware no longer knows is replaced at once. 0 = the kept-sessions pool above (one request per
# session at a time).
configurable int seawareSharedSessionSeconds = 600;

# Seconds the reservations of a guest are kept for POST /guest-profiles/{guestId}, shared by every
# copy through stateRedis; identical requests at the same time share one Seaware read. 0 = never kept
# (every request asks Seaware). With a value, a booking made in that time shows up that much later.
configurable int tripsCacheSeconds = 0;

# Seconds POST /guest-profiles/{guestId} waits for Seaware's reservations. When they are not there by
# then, the guest's answer goes out without trips (the shape of a guest with no trips) and with the
# header X-Trips-Pending: true; the lookup is not cancelled: it finishes in the background and its
# answer goes into the trips cache (tripsCacheSeconds), so the next call gets it. 0 = wait as long
# as Seaware takes (as before).
configurable decimal tripsDeadlineSeconds = 8;

# True: right after a verified login (POST /otp/verify) the reservations of the guest's CRM profiles
# (the contacts the login check found) are read in the background into the trips cache, so the first
# POST /guest-profiles/{guestId} after the sign-in is answered from it. The answer does not wait.
configurable boolean warmTripsAtSignIn = true;

# True: the one-time password e-mail is handed over after the answer was sent. Faster, but an
# e-mail the provider refuses is then only logged - the caller has already got 202.
configurable boolean otpEmailAfterAnswer = false;

# True: a few harmless read-only requests are run at start, and the service reports "ready" after
# them, so the first caller after a deployment does not wait.
configurable boolean warmUpAtStart = true;

# Redis for kept values (profile photos). With enabled = false they are kept in memory only.
configurable commons:RedisSettings stateRedis = {enabled: false};

# Profile photos kept between requests, keyed by contact id and the contact's Modified_Time, so a
# changed contact gets a fresh photo. A photo that could not be read is never kept.
#
# + enabled - Keep photos (owner's decision 2026-11-16)
# + ttlSeconds - How long a kept photo is used
# + memoryEntries - Most photos kept in memory when Redis is switched off
public type PhotoCacheSettings record {|
    boolean enabled = false;
    int ttlSeconds = 86400;
    int memoryEntries = 200;
|};

configurable PhotoCacheSettings photoCache = {};

# Guest Identity Resolution (plan v2.1). enabled = false (the default): POST /processGuestIdentity
# works exactly as before. enabled = true: a guest in the approved direct scope gets no IDs here -
# its CRM contact is upserted as PENDING_IDENTITY and its snapshot is handed to the identity
# integration service, which publishes guest.identity.evaluation.requested.v1; the Python decision
# service then gives it its Global and Loyalty IDs. Guests outside the scope keep today's flow.
#
# + enabled - Switch (owner decision: stays off until the cut-over)
# + sourceCodes - Approved direct booking source codes
# + agencyNames - Approved direct agencies
# + sourceCodeField - Field of the incoming guest with the booking source code (batch: sourceCode)
# + agencyNameField - Field of the incoming guest with the agency name (batch: agencyName)
# + sourceSystem - Source system written to the contact and the event
# + sourceCodeCrmField - CRM contact field for the source code; "" = not written (CRM spec: to confirm)
# + integration - The identity integration service (guest-identity-integration, role review)
# + ingressPath - Its ingress path
# + ingressToken - Token it expects in X-Webhook-Token
public type IdentityResolutionSettings record {|
    boolean enabled = false;
    string[] sourceCodes = ["INT-ASSC", "INT-CON", "NEWINT-CON", "MOBAPP", "WHATSAPP", "IN HOUSE"];
    string[] agencyNames = [
        "AROYA CRUISES MAIN OFFICE",
        "AROYA CRUISES MAIN OFFICE USD",
        "AROYA CRUISES MAIN OFFICE EUR",
        "AROYA CRUISES MAIN OFFICE GBP",
        "FUTURE CRUISES",
        "RIYADH SEASON",
        "WHATSAPP"
    ];
    string sourceCodeField = "sourceCode";
    string agencyNameField = "agencyName";
    string sourceSystem = "SEAWARE";
    string sourceCodeCrmField = "";
    commons:DownstreamSettings integration = {url: "http://localhost"};
    string ingressPath = "/guest-identity-integration/v1/crm-events";
    string ingressToken = "";
|};

configurable IdentityResolutionSettings identityResolution = {};
