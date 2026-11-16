import otalio_batch_proc_api.core;

import aroya/integration_commons as commons;

// Settings of the Otalio-to-CRM sync. Values live in Config.toml
// (deploy/vm/config/otalio-batch-proc-api.toml). The job starts by itself and writes to other
// systems, so it has a switch, and the switch is off unless set to true.

configurable string env = ?;
configurable int httpPort = 8081;
configurable string basePath = "/otalio-batch-proc-api/v1";

# The timed job (old flow: interfaceFlow).
configurable core:TimerSettings timer = {};

# The Otalio database the job reads from (read only).
configurable core:DbSettings db = {};
# CRM system service: every CRM write and search.
configurable commons:DownstreamSettings zohoSys = {url: ""};
# Guest service: creates or finds the guests of a booking.
configurable commons:DownstreamSettings guestIdentityProc = {url: ""};
# Database system service: stores rows for refused records (optional).
configurable commons:DownstreamSettings dbSys = {url: ""};
# Error e-mails (off unless enabled).
configurable commons:NotifySettings notify = {};
# Where the job remembers how far it got. Off: kept in memory and lost on restart.
configurable commons:RedisSettings stateRedis = {enabled: false, host: "", port: 6379};

configurable core:SyncSettings sync = {};
configurable core:CrmPaths crmPaths = {};

# Error e-mail of the old application (Global_Error_Handler -> internal-sys-exp-api-exceptionSub_Flow),
# field by field: subject "<env> - <app>", importance from the error type, batch_errors.txt attachment.
# Off by default: switching on sends real e-mails while the Mule application still sends its own.
configurable core:MailSettings mail = {};
