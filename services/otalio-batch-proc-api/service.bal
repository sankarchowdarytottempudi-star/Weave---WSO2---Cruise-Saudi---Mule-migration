import otalio_batch_proc_api.core;

import ballerina/http;
import ballerina/log;
import ballerina/task;
import ballerina/time;
import ballerinax/prometheus as _;


// otalio-batch-proc-api on WSO2 (Ballerina): the Otalio-to-CRM sync. Replaces the Mule project of
// the same name.
//
// One part, ported from the one flow of the old application that starts by itself (logic: modules/core):
//   interfaceFlow   timer   reads the bookings changed in the next slice of time from the Otalio
//                           database and writes them to the CRM (reservations, guests, links,
//                           spend transactions and items, cabins, voyages).
//
// The old application answered no addresses, and neither does this one (only /health).
//
// The timer starts by itself and writes to other systems, so it has a switch ([...timer] enabled)
// that is off by default. With the switch off no client is created, the database is not opened
// and nothing is called. With the switch on and a needed setting missing, or the database out of
// reach, the job is not started and the start-up line says why; the service itself keeps running.

listener http:Listener httpListener = new (httpPort);

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    log:printInfo("otalio-batch-proc-api starting", env = env, basePath = basePath, timer = startTimer(),
            progressKeptIn = stateRedis.enabled ? "Redis" : "memory (lost on restart)");
}

class TimerJob {
    *task:Job;
    private final core:OtalioSync sync;

    function init(core:OtalioSync sync) {
        self.sync = sync;
    }

    public function execute() {
        _ = self.sync.run();
    }
}

function startTimer() returns string {
    if !timer.enabled {
        return "off";
    }
    string[] notSet = [];
    if db.host == "" || db.username == "" {
        notSet.push("db.host/db.username");
    }
    if zohoSys.url == "" {
        notSet.push("zohoSys.url");
    }
    if guestIdentityProc.url == "" {
        notSet.push("guestIdentityProc.url");
    }
    if sync.mode != "delta" && (sync.fromDate == "" || sync.toDate == "") {
        notSet.push("sync.fromDate/sync.toDate");
    }
    if notSet.length() > 0 {
        return "NOT STARTED, settings not set: " + string:'join(", ", ...notSet);
    }
    core:MySqlRows|error otalio = new (db, sync);
    error? reachable = otalio is error ? otalio : otalio.ping();
    if otalio is error || reachable is error {
        // The driver's error text can contain the server address, so it is not written to the log.
        return "NOT STARTED, the database could not be reached with the configured address and account";
    }
    do {
        core:Backend? errorRows = dbSys.url == "" ? () : check new core:Backend("database system service", dbSys, sync);
        core:StateStore progress = check new (stateRedis, "otalio-batch:state:");
        core:OtalioSync job = new (progress, otalio, check new ("CRM system service", zohoSys, sync),
            check new ("guest service", guestIdentityProc, sync), errorRows, check new core:ErrorMail(mail), sync,
            crmPaths
        );
        time:Civil? firstRun = timer.startDelaySeconds > 0d
            ? time:utcToCivil(time:utcAddSeconds(time:utcNow(), timer.startDelaySeconds)) : ();
        // source-entry: interfaceFlow (switch: timer)
        _ = check task:scheduleJobRecurByFrequency(new TimerJob(job), timer.intervalSeconds, startTime = firstRun);
        return string `ON, every ${timer.intervalSeconds}s (mode ${sync.mode})`;
    } on fail error e {
        log:printError("The timed job could not be started", reason = e.message());
        return "NOT STARTED, see the error line above";
    }
}

// The old application had no addresses of its own; nothing is served under the base path.
final http:Service apiService = service object {
};

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}
