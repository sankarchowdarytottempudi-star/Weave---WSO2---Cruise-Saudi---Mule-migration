import otalio_sys_api_new.core;

import aroya/integration_commons as commons;

// Configuration of otalio-sys-api-new. Every value the old Mule project read from
// src/main/resources/{shore,ship}/{env}.yaml has a place here. Values live in the service's
// configuration Secret on the cluster, never in this repository.

# Environment name, for logs (Mule `env`).
configurable string env = ?;
configurable int httpPort = 8081;
# Path the API is served under (Mule listener path `${app.name}/v1/*`).
configurable string basePath = "/otalio-sys-api-new/v1";

# Otalio (Mule `OtalioConfigDetails.host`, HTTPS; timeout = `OtalioConfigDetails.responseTimeout`).
configurable commons:DownstreamSettings hTTPRequestOtalioSystemConfig = {url: "http://localhost", timeoutSeconds: 40};

# Otalio path of every operation a caller can name in `operationName`
# (Mule `OtalioConfigDetails.<operationName>.path`). `{ID}` in a path is replaced by `shipId`.
configurable map<string> operationPaths = {};
# Path of Otalio's GraphQL endpoint (Mule `OtalioConfigDetails.OtalioGQLPath`).
configurable string graphqlPath = "/apollo-server";

# Sign-in and token paths (Mule `OtalioConfigDetails.ssologin.path`, `ssologinRefresh.path`).
configurable string loginPath = "/iam/v1/sso/login";
configurable string refreshPath = "/iam/v1/sso/refresh";
# Account the service signs in to Otalio with (Mule secure properties `authToken.login`,
# `authToken.password`). An operation answers 503 while it is missing.
configurable core:OtalioAccount otalioAccount = {};
# Seconds the refresh token of a sign-in is reused (Mule `objectStore.entryTTL`).
configurable int refreshTokenSeconds = 1790;
# Longest time, in seconds, an access token is reused. 0 asks Otalio for a new access token on
# every call, as the Mule flow did.
configurable int accessTokenSeconds = 300;

# How many times a call that could not reach Otalio is repeated, and the pause between
# (Mule `error.httpRetryCount`, `error.httpRetryFrequency`).
configurable int httpRetryCount = 0;
configurable decimal httpRetryFrequencySeconds = 5;

# Kafka error records of failed calls (Mule global error handler, sub-flow `kafka`). Off by default:
# while the Mule application runs, both would publish the same records.
configurable commons:AuditSettings audit = {};

# Where the old object store's values live: Redis (enabled) or memory only (enabled = false).
configurable commons:RedisSettings stateRedis = {enabled: false};
