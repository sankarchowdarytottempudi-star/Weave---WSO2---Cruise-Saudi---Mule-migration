import aroya/integration_commons as commons;

// Migrated from cs-repo-email-sys-api-prod (mule4). The names follow the old property names
// (smtpZepto.*, smtp.*, client.*, error.httpRetry*) so the old settings map one to one.
// Account values (user, password, client id, client secret) are entered on the server with
//   bash /root/accept/email_account.sh
// and live only in the service's settings file. They are never written to a log.

configurable string env = ?;
configurable int httpPort = 8081;
configurable string basePath = "/email-sys-api/v1";
# Mule: mule.deploymentTarget. `shore` sends through the mail provider's HTTPS API, `ship` through the ship's mail server.
configurable string deploymentTarget = "shore";
configurable commons:RetryPolicy retryPolicy = {};
configurable commons:AuditSettings audit = {};

# Source: Send_Email_HTTP_Request_Config. The full https address of the provider's "send mail" call
# (Mule: https://<sendMailRequest.host>/<sendMailRequest.path>).
configurable commons:DownstreamSettings sendEmailHTTPRequestConfig = {url: "http://localhost"};
# Source: Token_HTTP_Request_Config. The full https address that issues the access token
# (Mule: https://<tokenRequest.host>/<tenentId>/<tokenRequest.path>).
configurable commons:DownstreamSettings tokenHTTPRequestConfig = {url: "http://localhost"};

# The application account for the provider's HTTPS API (Mule: client.id, client.secret, the scope
# written in AccessToken_SchedulerFlow, scheduler.frequency).
#
# + id - Application (client) id
# + secret - Client secret
# + scope - Scope asked for with the token
# + tokenMinutes - How long one token is used before a new one is asked for
public type MailClientSettings record {|
    string id = "";
    string secret = "";
    string scope = "";
    int tokenMinutes = 55;
|};

configurable MailClientSettings mailClient = {};

# Mule: error.httpRetryCount and error.httpRetryFrequency (milliseconds there, seconds here).
configurable int httpRetryCount = 2;
configurable decimal httpRetryFrequencySeconds = 5;

# One mail server.
#
# + host - Server name
# + port - Port (465: secure from the first byte)
# + user - Login, empty for a server that needs none
# + password - Password
# + fromAddress - The sender, as the old API wrote it (`"Name" <address>` or an address)
# + to - Fixed recipients (ship only; Mule smtp.email_to)
# + cc - Fixed copy recipients (ship only; Mule smtp.email_cc)
# + security - SSL, START_TLS_AUTO, START_TLS_ALWAYS or START_TLS_NEVER
# + caCertPath - Certificate file to trust when the server uses a private one
# + timeoutSeconds - Longest wait for the server to accept one message
public type SmtpSettings record {|
    string host = "";
    int port = 465;
    string user = "";
    string password = "";
    string fromAddress = "";
    string[] to = [];
    string[] cc = [];
    string security = "SSL";
    string caCertPath = "";
    decimal timeoutSeconds = 30;
|};

# Mule: Email_SMTP_Zepto, used when the caller sends the header `provider: exchange`.
configurable SmtpSettings smtpZepto = {};

# How messages for `provider: exchange` (one-time codes, welcome and summary e-mails) are handed to
# Zepto: "api" = ZeptoMail's HTTPS send API with the same account (the SMTP password is ZeptoMail's
# Send Mail token), "smtp" = the mail server as in the old application. The message is the same.
configurable string codeMailVia = "smtp";

# ZeptoMail's HTTPS send API.
#
# + url - API address; empty = taken from smtpZepto.host ("smtp." becomes "api."), over https
# + timeoutSeconds - Time the provider gets to take the message
# + token - ZeptoMail "Send Mail token" for the API (a secret: never logged, never answered);
#   empty = the SMTP password is used, as before
public type ZeptoApiSettings record {|
    string url = "";
    decimal timeoutSeconds = 15;
    string token = "";
|};

configurable ZeptoApiSettings zeptoApi = {};
# Mule: Email_SMTP, used on a ship.
configurable SmtpSettings smtp = {};

# Where the old object store's values live: Redis (enabled) or memory only (enabled = false).
configurable commons:RedisSettings stateRedis = {enabled: false};
