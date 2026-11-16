import zoho_sys_api.core;

import aroya/integration_commons as commons;

// Configuration of zoho-sys-api. Every value the old Mule project read from
// src/main/resources/shore/{env}.yaml has a place here. Values live in the service's
// configuration Secret on the cluster, never in this repository.

# Environment name, for logs (Mule `env`).
configurable string env = ?;
configurable int httpPort = 8081;
# Path the API is served under. Callers use {basePath}/zoho/... (Mule listener `${app.name}/v1/zoho/*`).
configurable string basePath = "/zoho-sys-api/v1";

# Zoho accounts service, which issues access tokens (Mule `httpRequest.zohoAccess.host`, HTTPS).
configurable commons:DownstreamSettings hTTPRequestZohoAccessConfig = {url: "http://localhost", timeoutSeconds: 120};
# Path of the token request (Mule `httpRequest.zohoAccess.tokenPath`).
configurable string tokenPath = "/oauth/v2/token";
# Zoho CRM (Mule `httpRequest.zohoCRM.host`, HTTPS; timeout = Mule `httpRequest.responseTimeOut`).
configurable commons:DownstreamSettings zohoCRMAPIConfig = {url: "http://localhost", timeoutSeconds: 120};

# Zoho OAuth client the service signs in with (Mule `httpRequest.zohoAccess.clientId`,
# `clientSecret`, `refreshToken`). An operation answers 503 while any of them is missing.
configurable core:ZohoAccount zohoAccount = {};

# Start of the Zoho path built from the caller's address: {crmPathPrefix}{module}[/{record id}].
configurable string crmPathPrefix = "/crm/v2/";
# Minutes an access token is reused before a new one is asked for (Mule object store, 55 minutes).
configurable int tokenMinutes = 55;
# How many times a call is repeated with a new access token after Zoho answers
# "invalid oauth token" (Mule `error.unauthorizedRetryCount`).
configurable int unauthorizedRetryCount = 3;

# Kafka error records of failed calls (Mule global error handler, sub-flow `kafka`). Off by default:
# while the Mule application runs, both would publish the same records.
configurable commons:AuditSettings audit = {};

# Where the old object store's values live: Redis (enabled) or memory only (enabled = false).
configurable commons:RedisSettings stateRedis = {enabled: false};
