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

# Seconds the reservations of a guest are kept for POST /guest-profiles/{guestId}. 0 = never kept
# (every request asks Seaware). With a value, a booking made in that time shows up that much later.
configurable int tripsCacheSeconds = 0;

# True: the one-time password e-mail is handed over after the answer was sent. Faster, but an
# e-mail the provider refuses is then only logged - the caller has already got 202.
configurable boolean otpEmailAfterAnswer = false;

# True: a few harmless read-only requests are run at start, and the service reports "ready" after
# them, so the first caller after a deployment does not wait.
configurable boolean warmUpAtStart = true;
