import financial_transactions_proc_api.core;

import aroya/integration_commons as commons;

// Configuration of financial-transactions-proc-api. Every value the old Mule project read from
// src/main/resources/{shore,ship}/{env}.yaml that the operations need has a place here. Values
// live in the service's configuration Secret on the cluster, never in this repository.
//
// The Mule project reached Telr, Otalio and Seaware through one internal address
// (`HTTP_Request_configuration`). Here each of them is its own service, so each has its own address.
// An operation whose backend address is not set answers 503 and names the setting.

# Environment name (Mule `mule.env`). "prod" selects the production card merchant.
configurable string env = ?;
configurable int httpPort = 8081;
# Path the API is served under (Mule listener path `${app.name}/v1/*`).
configurable string basePath = "/financial-transactions-proc-api/v1";

# Telr payment gateway system API (Mule `httpRequest.path.telrSessions` / `telrStatus`).
configurable commons:DownstreamSettings telrSysApi = {url: "http://localhost"};
configurable string telrSessionsPath = "/telr-pay-gw-sys-api/v1/sessions";
configurable string telrStatusPath = "/telr-pay-gw-sys-api/v1/status";

# Seaware system API (Mule `httpRequest.path.seawarePath`).
configurable commons:DownstreamSettings seawareSysApi = {url: "http://localhost"};
configurable string seawarePath = "/seaware-sys-api/v1/integration-tasks";

# Otalio system API (Mule `httpRequest.path.postTransaction|getFolio|checkImage|getArticles`).
configurable commons:DownstreamSettings otalioSysApi = {url: "http://localhost"};
configurable string otalioPath = "/otalio-sys-api-new/v1/integration-tasks";

# Adyen payment gateway system API. Source: HTTP_Request_Adyen-System-API
configurable commons:DownstreamSettings hTTPRequestAdyenSystemAPI = {url: "http://localhost"};
configurable string adyenBasePath = "/adyen-pay-gw-sys-api/v1";

# Database system API (payment context, payment-attempt audit, currency rates).
# Source: HTTP_DB_System_API_Config
configurable commons:DownstreamSettings hTTPDBSystemAPIConfig = {url: "http://localhost"};
configurable string dbSystemPath = "/db-sys-api/v1/db";

# How many times a payment is started again with a fresh login when Seaware says the service
# account's session is gone (Mule `error.sessionRetryCount`).
configurable int sessionRetryCount = 1;

# Seaware service account used when the caller sends no agent session in X-Seaware-Authorization
# (Mule `data.seawareUserName` / `data.seawarePassword`). Leave empty to require the caller's session.
configurable core:SeawareAgent seawareAgent = {};

// Kafka starting point "currency-rateFlow" (ratefeed.bal). Off unless enabled = true.
// Source: Kafka_Consumer_Config, UntilSuccess.*, email.*
configurable core:RateListenerSettings currencyRateListener = {};
// E-mail system API (alert e-mail for a skipped currency-rate message). Source: HTTP_Request_configuration
configurable commons:DownstreamSettings hTTPRequestConfiguration = {url: "http://localhost"};
configurable string emailApiPath = "/email-sys-api/v1/send-email-notification";

# Kafka error records of failed calls (Mule global error handler, sub-flow `kafka`). Off by default:
# while the Mule application runs, both would publish the same records.
configurable commons:AuditSettings audit = {};

# Error e-mail of a failed HTTP call (Mule Global_Error_Handler -> financial-transactions-proc-exceptionSub_Flow,
# async, on every error). Same body, recipients and e-mail system API as the currency-rate alert.
# Off by default: switching on sends real e-mails while the Mule application still sends its own.
#
# + enabled - Switch
type ErrorMailSettings record {|
    boolean enabled = false;
|};

configurable ErrorMailSettings errorMail = {};
