import aroya/integration_commons as commons;

// Settings of identity-support-exp-api ("Guest Login"), ported by hand from the Mule application.
// Values per environment: deploy/vm/config/identity-support-exp-api.toml.

configurable string env = ?;
configurable int httpPort = 8081;
configurable string basePath = "/identity-support-exp-api/v1";

# Guest Identity process API. Mule: HTTP_Request_configuration_internal and the
# `httpRequest.internal.*` paths (otpgenerate, otpverify, guestIdentityPath, guestProfile, guestClient).
configurable commons:DownstreamSettings guestIdentityProcApi = {url: "http://localhost"};
configurable string guestIdentityBasePath = "/guest-identity-proc-api/v1";

# Database system API, used only to look up the error mapping (Mule: HTTP_DB_System_API_Config,
# sub-flow fetch-errors-db). While no address is set a backend error is answered unchanged.
configurable commons:DownstreamSettings dbSystemApi = {url: "http://localhost"};
configurable string dbSystemPath = "/db-sys-api/v1/db";

# Mule: error.source and error.target, named in the answer when the error mapping cannot be read.
configurable string errorSource = "identity-support-exp-api";
configurable string errorTarget = "guest-identity-proc-api";

// Speed. Neither setting changes an answer.

# Seconds a looked-up error mapping (endpoint and status) is kept, so an error answer does not
# wait for the database system API each time. 0 = looked up every time, as before. A changed
# mapping row is answered that many seconds later.
configurable int errorMappingCacheSeconds = 300;

# True: one harmless read-only request is run at start, and the service reports "ready" after it,
# so the first caller after a deployment does not wait.
configurable boolean warmUpAtStart = true;

# After `errorMappingCacheSeconds` a kept error mapping is still answered at once while a fresh
# copy is read in the background; older than this it is read again before answering.
configurable int errorMappingStaleSeconds = 86400;

# True: at start, the error mappings of the operations without values in their path are read
# into the keep in the background (read-only look-ups), so no caller waits for the first one.
configurable boolean errorMappingPrefetch = true;

# Redis that keeps the error mappings for every copy of the service and over restarts
# (the platform's Redis, as batch's stateRedis). enabled = false: kept in memory only.
configurable commons:RedisSettings stateRedis = {enabled: false};
