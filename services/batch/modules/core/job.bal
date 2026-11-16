import ballerina/log;
import ballerina/random;
import ballerina/time;
import ballerina/uuid;

# Names under which the job remembers how far it got (the old object store keys).
public final readonly & string[] STATE_KEYS = ["batchStatus", "seawareStatus", "lastupdated", "currentDate",
    "seawareCursor", "seawareNextPage"];

const API_NAME = "batch";
const SESSION_EXPIRED = "Session context not found or expired";
# Where the Seaware session token is kept between runs (old object store key `access_Token`).
const TOKEN_KEY = "access_Token";

type Page record {|
    json[] edges;
    string cursor;
    string nextPage;
    Window window;
|};

# The sign-in request for Seaware.
#
# + login - Account
# + return - Request body
public isolated function loginBody(SeawareLogin login) returns json {
    return {
        "query": "mutation Login { login(role: ResAgent, login: \"" + login.username + "\", password: \"" + login.password
            + "\", totalTimeout: \"PT2H\", inactivityTimeout: \"PT2H\") { sessionGUID role username sourceCode token versionInfo"
            + " expiration { timeout inactivityTimeout expires autoExtend } } }"
    };
}

# The reservations query for one slice of time.
#
# + window - Slice and page position
# + pageSize - Reservations to ask for
# + return - Request body
public isolated function reservationsBody(Window window, int pageSize) returns json {
    string after = window.cursor == "0" || window.cursor == "" ? "last : 0" : "after : " + window.cursor;
    return {
        "query": "query Reservations {\n reservations(\n params: {updatedAt: {from: \"" + window.'from + "\", to: \""
            + window.to + "\" } } first : " + pageSize.toString() + "\n" + after + "\n" + RESERVATIONS_SELECTION,
        "variables": {}
    };
}

# The timed job: reads the reservations changed in the next slice of time from Seaware and writes
# them to the CRM, block by block.
public isolated class SeawareSync {
    private final StateStore state;
    private final Backend seaware;
    private final Backend zoho;
    private final Backend guests;
    private final Backend? db;
    private final ErrorMail mail;
    private final OssUploader oss;
    private final readonly & SeawareLogin login;
    private final readonly & SyncSettings sync;
    private final readonly & CrmPaths paths;
    private boolean busy = false;

    # + state - Where progress is remembered
    # + seaware - Reservation service (Seaware GraphQL)
    # + zoho - CRM system service
    # + guests - Guest service
    # + db - Database system service for error rows, () when not set
    # + mail - The old application's error e-mail
    # + oss - The old application's upload of every page to OSS
    # + login - Seaware account
    # + sync - Sync settings
    # + paths - CRM paths
    public isolated function init(StateStore state, Backend seaware, Backend zoho, Backend guests, Backend? db,
            ErrorMail mail, OssUploader oss, SeawareLogin login, SyncSettings sync, CrmPaths paths) {
        self.state = state;
        self.seaware = seaware;
        self.zoho = zoho;
        self.guests = guests;
        self.db = db;
        self.mail = mail;
        self.oss = oss;
        self.login = login.cloneReadOnly();
        self.sync = sync.cloneReadOnly();
        self.paths = paths.cloneReadOnly();
    }

    # One run. Never fails: problems are logged (and e-mailed when that is switched on).
    #
    # + return - Short outcome, also written to the log
    public isolated function run() returns string {
        lock {
            if self.busy {
                log:printInfo("Seaware sync skipped: the previous run has not finished");
                return "skipped: previous run still working";
            }
            self.busy = true;
        }
        string correlationId = uuid:createType4AsString();
        string|error outcome = self.cycle(correlationId);
        if outcome is error {
            // the old Global_Error_Handler: mark Seaware as done so the next run starts, and e-mail the error
            error? reset = self.state.put("seawareStatus", "Completed");
            [string, string, string] [errorType, description, details] = mailParts(outcome);
            string mailed = self.mail.send(errorType, description, details, "", correlationId);
            log:printError("Seaware sync run failed", correlationId = correlationId, reason = outcome.message(),
                    errorType = errorType, errorMail = mailed == "" ? "sent" : "not sent: " + mailed,
                    statusReset = reset is error ? "failed: " + reset.message() : "done");
        }
        lock {
            self.busy = false;
        }
        return outcome is error ? "failed: " + outcome.message() : outcome;
    }

    isolated function cycle(string correlationId) returns string|error {
        map<string> saved = check self.state.all(STATE_KEYS);
        string batchStatus = unquote(saved["batchStatus"] ?: "");
        string seawareStatus = unquote(saved["seawareStatus"] ?: "");
        if !(["", "Completed", "NotStarted"].indexOf(batchStatus) is int && ["", "Completed"].indexOf(seawareStatus) is int) {
            log:printInfo("Seaware sync skipped: an earlier run is still marked as in progress",
                    batchStatus = batchStatus, seawareStatus = seawareStatus);
            return "skipped: earlier run marked in progress";
        }
        check self.state.put("seawareStatus", "InProgress");
        Page page = check self.read(saved, correlationId);
        if page.edges.length() == 0 {
            log:printInfo("No data from seaware to process", correlationId = correlationId, 'from = page.window.'from,
                    to = page.window.to);
        } else {
            // old oss-implSub_Flow: the page is kept in OSS before it is written; a failed upload stops the run
            string kept = check self.oss.upload(page.edges, correlationId);
            if kept != "" {
                log:printInfo("Seaware page kept in OSS", correlationId = correlationId, objectName = kept);
            }
        }
        check self.state.put("seawareStatus", "Completed");
        int failedBlocks = 0;
        json[][] blocks = chunks(page.edges, self.sync.chunkSize);
        foreach json[] block in blocks {
            check self.state.put("batchStatus", "InProgress");
            Chunk c = {edges: block, correlationId, jobName: self.sync.mode};
            error? written = self.write(c);
            if written is error {
                // the old Batch_Step_Failure step: the block's records are kept with the error message
                // under "batch contact-<run>-<n>" (old Object_store_error); the run goes on
                failedBlocks += 1;
                string key = string `batch contact-${correlationId}-${check random:createIntInRange(0, 9999)}`;
                json[] kept = from json e in block select {"request": e, "errorMessage": written.message()};
                error? stored = self.state.put(key, kept.toJsonString());
                log:printError("Seaware sync: a block of reservations was not fully written", correlationId = correlationId,
                        reservations = block.length(), reason = written.message(),
                        keptAs = stored is error ? "not kept: " + stored.message() : key);
            }
        }
        check self.state.put("seawareCursor", page.cursor);
        check self.state.put("seawareNextPage", page.nextPage);
        check self.state.put("lastupdated", page.window.to);
        check self.state.put("batchStatus", "Completed");
        log:printInfo("Seaware sync run finished", correlationId = correlationId, 'from = page.window.'from,
                to = page.window.to, reservations = page.edges.length(), blocks = blocks.length(),
                failedBlocks = failedBlocks, morePages = page.nextPage);
        return string `done: ${page.edges.length()} reservation(s), ${failedBlocks} failed block(s)`;
    }

    isolated function read(map<string> saved, string correlationId) returns Page|error {
        Window window = check nextWindow(self.sync, saved, time:utcNow());
        check self.state.put("currentDate", {"from": window.'from, "to": window.to}.toJsonString());
        json body = reservationsBody(window, self.sync.pageSize);
        // improvement over the old flow (whose cache check never matched, so it signed in on every run):
        // the session token is kept and used again until Seaware says it has expired
        string kept = check self.state.get(TOKEN_KEY);
        boolean fresh = kept == "";
        string token = fresh ? check self.signIn(correlationId) : kept;
        Answer answer = check self.query(token, body, correlationId);
        if !fresh && (expired(answer) || answer.status == 401) {
            answer = check self.query(check self.signIn(correlationId), body, correlationId);
        } else if expired(answer) {
            answer = check self.query(check self.signIn(correlationId), body, correlationId);
        }
        if answer.status >= 400 || answer.unreadable {
            return error("Seaware refused the reservations query (" + answer.failure + ")",
                errorType = answer.status >= 400 ? statusType(answer.status) : "N/A", details = answer.failure);
        }
        json reservations = f(answer.body, "data", "reservations");
        if reservations is () && !blank(f(answer.body, "errors")) {
            return error("Seaware answered the reservations query with an error");
        }
        json hasNext = f(reservations, "pageInfo", "hasNextPage");
        return {
            edges: items(f(reservations, "edges")),
            cursor: textOr(f(reservations, "pageInfo", "endCursor"), ""),
            nextPage: hasNext is boolean ? hasNext.toString() : "",
            window
        };
    }

    isolated function signIn(string correlationId) returns string|error {
        Answer answer = check self.seaware.send("POST", {"Accept": "application/json", "correlationId": correlationId},
                loginBody(self.login));
        string? token = text(f(answer.body, "data", "login", "token"));
        if answer.status >= 400 || token is () || token == "" {
            return error("Seaware sign-in was refused", errorType = answer.status >= 400 ? statusType(answer.status) : "UNAUTHORIZED",
                details = answer.status >= 400 ? answer.failure : "no token in the answer");
        }
        check self.state.put(TOKEN_KEY, token);
        return token;
    }

    isolated function query(string token, json body, string correlationId) returns Answer|error {
        return self.seaware.send("POST", {"Authorization": "Bearer " + token, "correlationId": correlationId}, body);
    }

    // The CRM steps for one block, in the old application's order.
    isolated function write(Chunk c) returns error? {
        check self.writeReservations(c);
        check self.writeGuests(c);
        check self.writeLinks(c);
        check self.writeCabins(c);
        if self.sync.writeShorex {
            check self.writeShorex(c);
        }
        check self.writeAddons(c);
        check self.writeGroups(c);
        check self.writeVoyages(c);
        check self.writeInvoices(c);
        check self.writeReservations(c);
    }

    isolated function crm(string method, string path, json body, Chunk c, string label, boolean byApiName, int count)
            returns json|error {
        return crmWrite(self.zoho, method, path, body, c.correlationId, label, byApiName, count);
    }

    isolated function report(Chunk c, string step, map<json>[] rows) {
        if rows.length() == 0 {
            return;
        }
        string notWritten = writeErrorRows(self.db, self.sync.errorTable, rows, c.correlationId);
        log:printWarn("Seaware sync: records were refused", correlationId = c.correlationId, step = step,
                records = rows.length(), errorRows = notWritten == "" ? "written" : "not written: " + notWritten,
                reasons = refusalSummary(rows));
    }

    isolated function writeReservations(Chunk c) returns error? {
        c.reservationAnswer = check self.crm("POST", self.paths.reservations, reservationRequest(c), c, "reservation : ",
                true, c.edges.length());
        self.report(c, "Reservation", reservationErrors(c));
    }

    isolated function writeGuests(Chunk c) returns error? {
        c.contactAnswers = [];
        foreach json e in c.edges {
            json[] request = guestRequest(f(e, "node"), self.sync.identityScopeFields);
            Answer answer = check self.guests.send("POST", {"client_channel": "seawareBatch", "correlationId": c.correlationId},
                    request);
            c.contactAnswers.push(answer.status >= 400 || answer.unreadable ? guestRefusal(answer, request.length()) : answer.body);
        }
        self.report(c, "Guest", guestErrors(c));
    }

    isolated function writeLinks(Chunk c) returns error? {
        json[] existing = [];
        foreach json[] ids in chunks(reservationIds(c), 3) {
            existing.push(...check crmSearch(self.zoho, self.paths.reservationLinkingSearch,
                    anyOf("Reservation_Names:equals", ids), c.correlationId));
        }
        LinkingPlan plan = linkingPlan(c, existing);
        foreach json body in plan.creates {
            _ = check self.crm("POST", self.paths.reservationLinking, body, c, "Reservation Linking : ", true, 1);
        }
        foreach json body in plan.updates {
            _ = check self.crm("PUT", self.paths.reservationLinking, body, c, "Reservation Linking : ", true, 1);
        }
    }

    isolated function existingFor(Chunk c, string searchPath) returns json[]|error {
        json[] keys = from json e in c.edges select f(e, "node", "key");
        json[] existing = [];
        foreach json[] part in chunks(keys, 3) {
            existing.push(...check crmSearch(self.zoho, searchPath, anyOf("Name:in", part), c.correlationId));
        }
        return existing;
    }

    isolated function writeCabins(Chunk c) returns error? {
        json[] existing = check self.existingFor(c, self.paths.cabinInfoSearch);
        c.cabinCorrelation = [];
        map<json>[] rows = [];
        foreach Group g in byReservation(ownedMerge(cabinRecords(c), existing)) {
            json[] send = writable(g);
            json answer = ();
            if send.length() > 0 {
                answer = check self.crm("POST", self.paths.cabinInfo, cabinRequest(send), c, "CabinInfo : ", false, send.length());
            }
            json[] answers = answersFor(g, answer);
            c.cabinCorrelation.push(cabinCorrelation(g, answers));
            rows.push(...cabinErrors(c, g, answers));
        }
        self.report(c, "Cabin", rows);
    }

    isolated function writeAddons(Chunk c) returns error? {
        json[] existing = check self.existingFor(c, self.paths.addonsSearch);
        map<json>[] rows = [];
        foreach Group g in byReservation(ownedMerge(addonRecords(c), existing)) {
            json[] send = writable(g);
            json answer = ();
            if send.length() > 0 {
                answer = check self.crm("POST", self.paths.addons, {"data": send}, c, "Addons : ", false, send.length());
            }
            rows.push(...addonErrors(c, g, answersFor(g, answer)));
        }
        self.report(c, "Addons", rows);
    }

    isolated function writeShorex(Chunk c) returns error? {
        json[] existing = check self.existingFor(c, self.paths.shorexSearch);
        map<json>[] rows = [];
        foreach Group g in byReservation(ownedMerge(shorexRecords(c), existing)) {
            json[] send = writable(g);
            json answer = ();
            if send.length() > 0 {
                answer = check self.crm("POST", self.paths.shorex, upsertBody(send, "Name"), c, "Shorex : ", true, send.length());
            }
            rows.push(...shorexErrors(c, g, answersFor(g, answer)));
        }
        self.report(c, "Shorex", rows);
    }

    isolated function writeGroups(Chunk c) returns error? {
        c.groupAnswer = check self.crm("POST", self.paths.groupAgency, groupRequest(c), c, "Group-Agency : ", false,
                c.edges.length());
        self.report(c, "Group-Agency", groupErrors(c));
    }

    isolated function writeVoyages(Chunk c) returns error? {
        c.voyageAnswers = [];
        foreach json e in c.edges {
            c.voyageAnswers.push(check self.crm("POST", self.paths.voyages, voyageRequest(f(e, "node")), c, "voyages : ", true, 1));
        }
        self.report(c, "Voyage", voyageErrors(c));
    }

    isolated function writeInvoices(Chunk c) returns error? {
        c.invoiceAnswer = check self.crm("POST", self.paths.invoices, invoiceRequest(c), c, "invoice : ", true,
                c.edges.length());
        self.report(c, "Invoice", invoiceErrors(c));
    }
}

isolated function expired(Answer answer) returns boolean {
    return textOr(at(f(answer.body, "errors", "message"), 0), "").includes(SESSION_EXPIRED);
}


# Why records were refused, for the log: each distinct error code with its count and the target
# system's message, cut short. Never a value of a record: digits and mailboxes are masked.
#
# + rows - The error rows of one step
# + return - For example `INVALID_DATA x3 (invalid data); DUPLICATE_DATA x1 (duplicate data)`
isolated function refusalSummary(map<json>[] rows) returns string {
    map<int> counts = {};
    map<string> messages = {};
    string[] keys = [];
    foreach map<json> row in rows {
        json code = row["error_code"];
        string key = code is () ? "?" : code.toString();
        if !counts.hasKey(key) {
            keys.push(key);
            json reason = row["failure_reason"];
            string text = reason is string ? reason : (reason is () ? "" : reason.toJsonString());
            text = re `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+`.replaceAll(text, "<mailbox>");
            text = re `[0-9]{3,}`.replaceAll(text, "<n>");
            messages[key] = text.length() > 90 ? text.substring(0, 90) : text;
        }
        counts[key] = (counts[key] ?: 0) + 1;
    }
    string[] parts = [];
    foreach string key in keys {
        parts.push(key + " x" + (counts[key] ?: 0).toString() + " (" + (messages[key] ?: "") + ")");
    }
    return string:'join("; ", ...parts);
}
