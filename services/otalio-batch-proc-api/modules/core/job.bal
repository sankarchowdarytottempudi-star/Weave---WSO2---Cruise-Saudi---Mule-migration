
import ballerina/log;
import ballerina/time;
import ballerina/uuid;

# Names under which the job remembers how far it got (the old object store keys).
public final readonly & string[] STATE_KEYS = ["otalioStatus", "batchStatus", "lastupdated", "currentDate"];

const API_NAME = "otalio-batch-proc-api";

# The timed job: reads the bookings changed in the next slice of time from the Otalio database
# and writes them to the CRM, block by block.
public isolated class OtalioSync {
    private final StateStore state;
    private final RowSource otalio;
    private final Backend zoho;
    private final Backend guests;
    private final Backend? db;
    private final ErrorMail mail;
    private final readonly & SyncSettings sync;
    private final readonly & CrmPaths paths;
    private boolean busy = false;

    # + state - Where progress is remembered
    # + otalio - The Otalio database
    # + zoho - CRM system service
    # + guests - Guest service
    # + db - Database system service for error rows, () when not set
    # + mail - The old application's error e-mail (Global_Error_Handler)
    # + sync - Sync settings
    # + paths - CRM paths
    public isolated function init(StateStore state, RowSource otalio, Backend zoho, Backend guests, Backend? db,
            ErrorMail mail, SyncSettings sync, CrmPaths paths) {
        self.state = state;
        self.otalio = otalio;
        self.zoho = zoho;
        self.guests = guests;
        self.db = db;
        self.mail = mail;
        self.sync = sync.cloneReadOnly();
        self.paths = paths.cloneReadOnly();
    }

    # One run. Never fails: problems are logged (and e-mailed when that is switched on).
    #
    # + return - Short outcome, also written to the log
    public isolated function run() returns string {
        lock {
            if self.busy {
                log:printInfo("Otalio sync skipped: the previous run has not finished");
                return "skipped: previous run still working";
            }
            self.busy = true;
        }
        string|error outcome = self.cycle();
        lock {
            self.busy = false;
        }
        if outcome is error {
            log:printError("Otalio sync run failed", reason = outcome.message());
            // Mule: an error that leaves the scheduler flow reaches Global_Error_Handler, which sends
            // the error e-mail (internal-sys-exp-api-exceptionSub_Flow); the attachment is the error payload
            [string, string, string] [errorType, description, details] = mailParts(outcome);
            _ = self.mail.send(errorType, description, details, details, uuid:createType4AsString());
            return "failed: " + outcome.message();
        }
        return outcome;
    }

    isolated function cycle() returns string|error {
        map<string> saved = check self.state.all(STATE_KEYS);
        string otalioStatus = unquote(saved["otalioStatus"] ?: "");
        string batchStatus = unquote(saved["batchStatus"] ?: "");
        if !(["", "Completed"].indexOf(otalioStatus) is int && ["", "Completed"].indexOf(batchStatus) is int) {
            log:printInfo("Otalio sync skipped: an earlier run is still marked as in progress",
                    otalioStatus = otalioStatus, batchStatus = batchStatus);
            return "skipped: earlier run marked in progress";
        }
        string correlationId = uuid:createType4AsString();
        check self.state.put("otalioStatus", "InProgress");
        [Window, json[]]|error read = self.changedBookings(saved, correlationId);
        check self.state.put("otalioStatus", "Completed");
        if read is error {
            return read;
        }
        [Window, json[]] [window, bookings] = read;
        if bookings.length() == 0 {
            log:printInfo("No data from Otalio to process", correlationId = correlationId, 'from = window.'from,
                    to = window.to);
        }
        int failedBlocks = 0;
        int guestRows = 0;
        json[][] blocks = chunks(bookings, self.sync.chunkSize);
        foreach json[] block in blocks {
            int|error written = self.block(block, correlationId);
            if written is error {
                failedBlocks += 1;
                log:printError("Otalio sync: a block of bookings was not fully written", correlationId = correlationId,
                        bookings = block.length(), reason = written.message());
                // Mule: a failed block stays inside the batch job (maxFailedRecords -1) and never reaches
                // the global error handler, so it sends no e-mail
            } else {
                guestRows += written;
            }
        }
        check self.state.put("lastupdated", window.to);
        check self.state.put("batchStatus", "Completed");
        log:printInfo("Otalio sync run finished", correlationId = correlationId, 'from = window.'from, to = window.to,
                bookings = bookings.length(), guestRows = guestRows, blocks = blocks.length(), failedBlocks = failedBlocks);
        return string `done: ${bookings.length()} booking(s), ${guestRows} guest row(s), ${failedBlocks} failed block(s)`;
    }

    // The read phase: which bookings changed in the next slice of time.
    isolated function changedBookings(map<string> saved, string correlationId) returns [Window, json[]]|error {
        Window window = check nextWindow(self.sync, saved, time:utcNow());
        check self.state.put("currentDate", {"from": window.'from, "to": window.to}.toJsonString());
        json[] found = check self.otalio.rows(changedBookingsQuery(self.sync.skipBookingNumbers, queryTime(window.'from),
                queryTime(window.to)));
        [json[], json[]] [good, bad] = splitBookings(found);
        self.report(correlationId, "Reservation (booking number)", invalidBookingRows(bad, correlationId, self.sync.mode));
        return [window, good];
    }

    // One block of bookings: read their guest rows, then the CRM steps in the old application's order.
    isolated function block(json[] bookings, string correlationId) returns int|error {
        json[] rows = check self.guestRows(bookings);
        if rows.length() == 0 {
            return 0;
        }
        json[] accounts = check crmSearch(self.zoho, self.paths.accountSearch, accountCriteria(rows), correlationId);
        self.report(correlationId, "Mismatch", mismatchRows(rows, accounts, correlationId, self.sync.mode));
        check self.state.put("batchStatus", "InProgress");
        Block b = {rows, correlationId, jobName: self.sync.mode};
        check self.writeReservations(b);
        check self.writeGuests(b);
        check self.writeLinks(b);
        check self.findVoyages(b);
        check self.writeSpend(b);
        check self.writeSpendItems(b);
        check self.writeCabins(b);
        check self.writeVoyages(b);
        check self.writeReservations(b);
        return rows.length();
    }

    isolated function guestRows(json[] bookings) returns json[]|error {
        json[] rows = check self.otalio.rows(reservationRowsQuery(sqlList(from json b in bookings select f(b, "booking_number"))));
        if rows.length() == 0 {
            return rows;
        }
        string ids = sqlList(from json row in rows select f(row, "id"));
        json[] revenue = check self.otalio.rows(revenueQuery(ids));
        json[] transactions = check self.otalio.rows(transactionsQuery(ids));
        json[] postingItems = check self.otalio.rows(postingItemsQuery(sqlList(from json t in transactions select f(t, "id"))));
        return attach(rows, revenue, transactions, postingItems);
    }

    isolated function report(string correlationId, string step, map<json>[] rows) {
        if rows.length() == 0 {
            return;
        }
        string notWritten = writeErrorRows(self.db, self.sync.errorTable, rows, correlationId);
        log:printWarn("Otalio sync: records were refused or differ", correlationId = correlationId, step = step,
                records = rows.length(), errorRows = notWritten == "" ? "written" : "not written: " + notWritten);
    }

    // Writes records in requests of at most `blockSize`; gives one answer entry per record.
    isolated function upsert(Block b, string path, json[] records, string checkField, boolean workflow, string label,
            boolean byApiName) returns json[]|error {
        json[] out = [];
        foreach json[] part in chunks(records, self.sync.blockSize) {
            json answer = check crmWrite(self.zoho, "POST", path, upsertBody(part, checkField, workflow), b.correlationId,
                    label, byApiName, part.length());
            out.push(...aligned(f(answer, "data"), part.length()));
        }
        return out;
    }

    isolated function writeReservations(Block b) returns error? {
        b.reservationData = check self.upsert(b, self.paths.reservations, reservationRecords(b), "Account_Name", true,
                "reservation : ", true);
        self.report(b.correlationId, "Reservation", refusedRows(b, "Reservation", b.reservationData));
    }

    isolated function writeGuests(Block b) returns error? {
        json[] request = guestRequest(b.rows);
        Answer answer = check self.guests.send("POST", {"client_channel": "otalioBatch", "correlationId": b.correlationId},
                request);
        b.guestAnswers = answer.status >= 400 || answer.unreadable ? guestRefusal(answer, request.length())
            : items(answer.body);
        self.report(b.correlationId, "Guest", guestErrors(b));
    }

    isolated function writeLinks(Block b) returns error? {
        json[] existing = [];
        foreach json[] ids in chunks(reservationIds(b), 15) {
            existing.push(...check crmSearch(self.zoho, self.paths.reservationLinkingSearch,
                    anyOf("Reservation_Names:equals", ids), b.correlationId));
        }
        LinkingPlan plan = linkingPlan(b, existing);
        foreach json body in plan.creates {
            _ = check crmWrite(self.zoho, "POST", self.paths.reservationLinking, body, b.correlationId,
                    "Reservation Linking : ", true, 1);
        }
        foreach json body in plan.updates {
            _ = check crmWrite(self.zoho, "PUT", self.paths.reservationLinking, body, b.correlationId,
                    "Reservation Linking : ", true, 1);
        }
    }

    isolated function findVoyages(Block b) returns error? {
        json[] found = [];
        foreach json query in voyageDateQueries(b.rows) {
            Answer answer = check self.zoho.send("POST", {"zohoPath": self.paths.coql, "correlationId": b.correlationId},
                    query);
            if answer.status >= 400 || answer.unreadable {
                continue;
            }
            json body = answer.body;
            json[] voyages = body is json[] ? body : items(f(body, "data"));
            found.push(...voyages);
        }
        b.crmVoyages = crmVoyages(found);
    }

    isolated function writeSpend(Block b) returns error? {
        b.spendAnswers = [];
        foreach int i in 0 ..< b.rows.length() {
            json[] records = spendRecords(b, i);
            b.spendAnswers.push(records.length() == 0 ? [] : check self.upsert(b, self.paths.spendTransactions, records,
                    "Name", false, "spendTransactions : ", true));
        }
        self.report(b.correlationId, "Spend Transactions", spendErrors(b));
    }

    isolated function writeSpendItems(Block b) returns error? {
        map<json>[] rows = [];
        foreach ItemGroup g in spendItemGroups(b) {
            json[] answers = check self.upsert(b, self.paths.spendItems, g.records, "Name", false, "SpendItems : ", true);
            rows.push(...spendItemErrors(b, g, answers));
        }
        self.report(b.correlationId, "Spend Articles", rows);
    }

    isolated function writeCabins(Block b) returns error? {
        json[] existing = [];
        foreach json[] part in chunks(cabinBookings(b.rows), 15) {
            existing.push(...check crmSearch(self.zoho, self.paths.cabinInfoSearch, anyOf("Reservation.name:in", part),
                    b.correlationId));
        }
        Group[] groups = cabinGroups(b, existing);
        json[][] answers = [];
        foreach Group g in groups {
            answers.push(check self.upsert(b, self.paths.cabinInfo, g.records, "Name", true, "CabinInfo : ", false));
        }
        self.report(b.correlationId, "Cabin", cabinErrors(b, groups, answers));
    }

    isolated function writeVoyages(Block b) returns error? {
        b.voyageData = check self.upsert(b, self.paths.voyages, voyageRecords(b), "Name", true, "voyages : ", true);
        self.report(b.correlationId, "Voyage", refusedRows(b, "Voyage", b.voyageData));
    }
}
