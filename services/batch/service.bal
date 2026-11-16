import batch.core;

import ballerina/http;
import ballerina/lang.runtime;
import ballerina/log;
import ballerina/task;
import ballerina/time;
import ballerinax/activemq.driver as _;
import ballerinax/java.jms;
import ballerinax/prometheus as _;

// batch on WSO2 (Ballerina): the Seaware-to-CRM sync. Replaces the Mule project of the same name.
//
// Three parts, each ported from one flow of the old application (logic: modules/core):
//   interfaceFlow   timer   reads the reservations changed in the next slice of time from Seaware
//                           and writes them to the CRM (reservations, guests, links, cabins, add-ons,
//                           groups, voyages, invoices).
//   active-MQFlow   queue   one Seaware reservation notification -> reservation and invoice in the CRM.
//   interfaceFlow1  HTTP    {basePath}/clearObjectStore forgets how far the timer job got.
//
// The timer and the queue start by themselves and write to other systems, so each has a switch
// ([...timer] enabled, [...queue] enabled) that is off by default. With a switch off that part
// creates no client and calls nothing. With a switch on and a needed setting missing, the part is
// not started and the start-up line says which setting is missing; the service itself keeps running.

listener http:Listener httpListener = new (httpPort);

core:StateStore? stateStore = ();

function progress() returns core:StateStore|error {
    lock {
        core:StateStore? current = stateStore;
        if current is core:StateStore {
            return current;
        }
        core:StateStore created = check new (stateRedis, "batch:state:");
        stateStore = created;
        return created;
    }
}

function init() returns error? {
    check httpListener.attach(apiService, basePath);
    log:printInfo("batch starting", env = env, basePath = basePath, timer = startTimer(), queue = startQueue(),
            progressKeptIn = stateRedis.enabled ? "Redis" : "memory (lost on restart)");
}

class TimerJob {
    *task:Job;
    private final core:SeawareSync sync;

    function init(core:SeawareSync sync) {
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
    if reservationProc.url == "" {
        notSet.push("reservationProc.url");
    }
    if zohoSys.url == "" {
        notSet.push("zohoSys.url");
    }
    if guestIdentityProc.url == "" {
        notSet.push("guestIdentityProc.url");
    }
    if seawareLogin.username == "" || seawareLogin.password == "" {
        notSet.push("seawareLogin");
    }
    if sync.mode != "delta" && (sync.fromDate == "" || sync.toDate == "") {
        notSet.push("sync.fromDate/sync.toDate");
    }
    if notSet.length() > 0 {
        return "NOT STARTED, settings not set: " + string:'join(", ", ...notSet);
    }
    do {
        core:Backend? db = dbSys.url == "" ? () : check new core:Backend("database system service", dbSys, sync);
        core:SeawareSync job = new (check progress(), check new ("reservation service", reservationProc, sync),
            check new ("CRM system service", zohoSys, sync), check new ("guest service", guestIdentityProc, sync), db,
            check new core:ErrorMail(mail), check new core:OssUploader(oss), seawareLogin, sync, crmPaths
        );
        time:Civil? firstRun = timer.startDelaySeconds > 0d
            ? time:utcToCivil(time:utcAddSeconds(time:utcNow(), timer.startDelaySeconds)) : ();
        // source-entry: interfaceFlow (switch: timer)
        _ = check task:scheduleJobRecurByFrequency(new TimerJob(job), timer.intervalSeconds, startTime = firstRun);
        return string `ON, every ${timer.intervalSeconds}s (mode ${sync.mode}, error e-mail ${mail.enabled && mail.url != "" ? "on" : "off"}, OSS copy ${oss.enabled && oss.url != "" ? "on" : "off"})`;
    } on fail error e {
        log:printError("The timed job could not be started", reason = e.message());
        return "NOT STARTED, see the error line above";
    }
}

service class QueueService {
    *jms:Service;
    private final core:QueueWork work;

    function init(core:QueueWork work) {
        self.work = work;
    }

    remote function onMessage(jms:Message message) returns error? {
        string content;
        if message is jms:TextMessage {
            content = message.content;
        } else if message is jms:BytesMessage {
            content = check string:fromBytes(message.content);
        } else {
            log:printWarn("Queue message skipped: it is neither text nor bytes");
            return;
        }
        error? outcome = self.work.process(content);
        if outcome is error {
            log:printError("Queue message could not be processed", reason = outcome.message());
        }
    }
}

function startQueue() returns string {
    if !queue.enabled {
        return "off";
    }
    string[] notSet = [];
    if queue.brokerUrl == "" {
        notSet.push("queue.brokerUrl");
    }
    if queue.topic == "" {
        notSet.push("queue.topic");
    }
    if zohoSys.url == "" {
        notSet.push("zohoSys.url");
    }
    if notSet.length() > 0 {
        return "NOT STARTED, settings not set: " + string:'join(", ", ...notSet);
    }
    do {
        core:QueueWork work = new (check new ("CRM system service", zohoSys, sync), crmPaths);
        string providerUrl = queue.clientId == "" ? queue.brokerUrl
            : queue.brokerUrl + (queue.brokerUrl.includes("?") ? "&" : "?") + "jms.clientID=" + queue.clientId;
        jms:ConnectionConfiguration connectionConfig = {
            initialContextFactory: "org.apache.activemq.jndi.ActiveMQInitialContextFactory",
            providerUrl
        };
        if queue.username != "" {
            connectionConfig.username = queue.username;
            connectionConfig.password = queue.password;
        }
        // source-entry: active-MQFlow (switch: queue)
        jms:Listener queueListener = check new ({
            connectionConfig,
            consumerOptions: {destination: {'type: jms:TOPIC, name: queue.topic}}
        });
        check queueListener.attach(new QueueService(work));
        check queueListener.'start();
        runtime:registerListener(queueListener);
        return "ON";
    } on fail {
        // The broker's error text can contain its address, so it is not written to the log.
        return "NOT STARTED, the broker could not be reached with the configured address and account";
    }
}

final http:Service apiService = service object {
    // source-entry: interfaceFlow1
    resource function 'default clearObjectStore() returns json|http:InternalServerError {
        core:StateStore|error store = progress();
        error? cleared = store is error ? store : store.clear(core:STATE_KEYS);
        if cleared is error {
            log:printError("Object store could not be cleared", reason = cleared.message());
            return <http:InternalServerError>{body: {message: "Object store could not be cleared"}};
        }
        log:printInfo("Object store cleared");
        return {message: "Object store cleared"};
    }
};

service /health on httpListener {
    isolated resource function get live() returns json => {status: "UP"};

    isolated resource function get ready() returns json => {status: "UP"};
}
