import batch.core;

import aroya/integration_commons as commons;

// Settings of the Seaware-to-CRM sync. Values live in Config.toml (deploy/vm/config/batch.toml).
// Every part that starts by itself has its own switch, and every switch is off unless set to true.

configurable string env = ?;
configurable int httpPort = 8081;
configurable string basePath = "/batch/v1";

# The timed job (old flow: interfaceFlow).
configurable core:TimerSettings timer = {};
# The queue listener (old flow: active-MQFlow).
configurable core:QueueSettings queue = {};

# Reservation service: Seaware sign-in and the reservations query.
configurable commons:DownstreamSettings reservationProc = {url: ""};
# CRM system service: every CRM write and search.
configurable commons:DownstreamSettings zohoSys = {url: ""};
# Guest service: creates or finds the guests of a reservation.
configurable commons:DownstreamSettings guestIdentityProc = {url: ""};
# Database system service: stores rows for refused records (optional).
configurable commons:DownstreamSettings dbSys = {url: ""};
# The old application's error e-mail (Global_Error_Handler -> e-mail system service).
configurable core:MailSettings mail = {};
# The old application's copy of every page of reservations in an OSS bucket (oss-implSub_Flow).
configurable core:OssSettings oss = {};
# Where the job remembers how far it got. Off: kept in memory and lost on restart.
configurable commons:RedisSettings stateRedis = {enabled: false, host: "", port: 6379};

configurable core:SeawareLogin seawareLogin = {};
configurable core:SyncSettings sync = {};
configurable core:CrmPaths crmPaths = {};
