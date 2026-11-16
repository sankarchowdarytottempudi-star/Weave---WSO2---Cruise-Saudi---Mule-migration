import aroya/integration_commons as commons;

// Configuration. Every Mule property of src/main/resources/{shore,ship}/{env}.yaml has a
// place here; the mapping is in docs/generated/seaware-sys-api/MAPPING.md.

# Environment name, for logs and metrics (Mule `mule.env`).
configurable string env = ?;
# `shore` or `ship` (Mule `mule.deploymentTarget`).
configurable string deploymentTarget = "shore";
configurable int httpPort = 8081;
# Path the API is served under (Mule listener path `${app.name}/v1/*`).
configurable string basePath = "/seaware-sys-api/v1";

# Seaware GraphQL endpoint (Mule `httpRequest.host`/`port`/`path`, HTTPS).
configurable commons:DownstreamSettings seaware = {url: "https://localhost:3000", timeoutSeconds: 35, http2: true};
configurable string seawarePath = "/graphql";
# Time allowed for a write (a GraphQL mutation such as `reservationStore`). A write is sent to
# Seaware once: when it fails or runs out of time it is not sent again, because the first one
# may still finish there.
configurable decimal writeTimeoutSeconds = 55;

# Mule `error.httpRetryCount` / `httpRetryFrequency` / `httpErrorTypes`.
configurable commons:RetryPolicy retryPolicy = {};

# Mule `kafka.*`. Off in every Mule environment today.
configurable commons:AuditSettings audit = {};

# When Seaware answers an error, return its body unchanged with its status (Mule
# `error.target_error`, default true), instead of the platform error envelope.
configurable boolean passThroughDownstreamErrors = true;
