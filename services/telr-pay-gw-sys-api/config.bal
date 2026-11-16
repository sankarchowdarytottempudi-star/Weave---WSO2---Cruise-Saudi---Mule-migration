import telr_pay_gw_sys_api.core;

import aroya/integration_commons as commons;

// Configuration of telr-pay-gw-sys-api. Every value the old Mule project read from
// src/main/resources/{shore,ship}/{env}.yaml has a place here. Values live in the service's
// configuration Secret on the cluster, never in this repository.

# Environment name, for logs (Mule `env`).
configurable string env = ?;
configurable int httpPort = 8081;
# Path the API is served under (Mule listener path `${app.name}/v1/*`).
configurable string basePath = "/telr-pay-gw-sys-api/v1";

# Telr gateway address (Mule `TelrConfigDetails.host`, HTTPS). The service refuses to start
# while this is still the placeholder, so it can never be deployed half-configured.
configurable commons:DownstreamSettings hTTPRequestConfigurationTelr = {url: "http://localhost"};
# Path of the Telr order endpoint (Mule `TelrConfigDetails.path`).
configurable string telrPath = ?;

# Store identity and the fixed values the Mule project added to every Telr request
# (Mule `stores.*`, `method.*`, `framed`, `order.test`, `telr.returnUrls.*`). Required.
configurable core:TelrStore telrStore = ?;

# Kafka error records of failed calls (Mule global error handler, sub-flow `kafka`). Off by default:
# while the Mule application runs, both would publish the same records.
configurable commons:AuditSettings audit = {};
