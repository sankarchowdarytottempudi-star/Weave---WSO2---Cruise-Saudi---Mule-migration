import payment_reconciliation_proc_api.core;

import aroya/integration_commons as commons;

// Settings of payment-reconciliation-proc-api. The names follow the old application's settings
// (paymentReconciliation.*, dbSysApi.*, financialTransactions.*, emailSysApi.*).

configurable string env = ?;
configurable int httpPort = 8081;
configurable string basePath = "/payment-reconciliation-proc-api";

# The timer of the reconciliation job.
#
# + enabled - Off by default. Switch it on only after the old job has been stopped: two jobs would
# hand the same payments to process-payment twice
# + frequencyMinutes - Minutes between two runs (Mule: paymentReconciliation.scheduler.frequencyMinutes)
type SchedulerSettings record {|
    boolean enabled = false;
    int frequencyMinutes = 2;
|};

# Where the audit rows are read (Mule: dbSysApi.*).
#
# + dbPath - Path of the database system API
# + connectionKey - Its connection name
# + sessionId - Session id sent as parameter of the statement
type DbSettings record {|
    string dbPath = "/db-sys-api/v1/db";
    string connectionKey = "";
    string sessionId = "";
|};

# How process-payment is called (Mule: financialTransactions.*).
#
# + processPaymentPath - Path of process-payment
# + clientChannel - Value of the `client_channel` header
type PaymentSettings record {|
    string processPaymentPath = "/financial-transactions-proc-api/v1/process-payment";
    string clientChannel = "scheduler";
|};

# The summary e-mail of a run (Mule: paymentReconciliation.email.enabled and emailSysApi.*).
#
# + enabled - Off by default, as in the old settings
# + sendEmailPath - Path of the e-mail system API
# + provider - Value of the `provider` header
# + to - Recipients, separated by commas
# + subjectPrefix - Start of the subject
type EmailSettings record {|
    boolean enabled = false;
    string sendEmailPath = "/email-sys-api/v1/send-email-notification";
    string provider = "exchange";
    string to = "";
    string subjectPrefix = "Payment reconciliation";
|};

configurable SchedulerSettings scheduler = {};
configurable core:QuerySettings query = {};
configurable DbSettings dbSysApi = {};
configurable PaymentSettings financialTransactions = {};
configurable EmailSettings email = {};

// Backends. An address that is not set stays on the placeholder; the timer then does not start
// and the start-up line names the setting.

# Source: DB_Sys_API_HTTP_Request_Config - the database system API the audit rows are read through.
configurable commons:DownstreamSettings dBSysAPIHTTPRequestConfig = {url: "http://localhost"};
# Source: Financial_Transactions_HTTP_Request_Config - process-payment (Mule waited 60 s for its answer).
configurable commons:DownstreamSettings financialTransactionsHTTPRequestConfig = {url: "http://localhost", timeoutSeconds: 60};
# Source: Email_Sys_API_HTTP_Request_Config - the e-mail system API; only used while email.enabled is true.
configurable commons:DownstreamSettings emailSysAPIHTTPRequestConfig = {url: "http://localhost"};
