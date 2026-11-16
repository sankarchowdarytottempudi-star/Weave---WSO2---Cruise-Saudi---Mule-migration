
import ballerina/os;
import ballerina/test;
import ballerina/time;

// ---------------------------------------------------------------- sample data (made up)

function guestRow(string id, string booking, string clientId, string cabin) returns map<json> => {
    "id": id,
    "booking_number": booking,
    "clientId": clientId,
    "profile_id": "P-" + clientId,
    "Cabin_Code": cabin,
    "cruise_product": "PKG-OTALIO",
    "reservation_status_id": "CHECKED_IN",
    "first_name": "First" + clientId,
    "last_name": "Last",
    "dateOfBirth": "1990-02-03",
    "email": clientId.toLowerAscii() + "@example.test",
    "nationality": "Atlantis",
    "phone_number": "+966501234567",
    "city": "Port City",
    "STATE": "never read from here",
    "state": "Coast",
    "issue_date": "2020-01-02T00:00:00",
    "expiry_date": "2030-01-02T00:00:00",
    "is_primary_document": "1",
    "preferred_communication_method": "E_MAIL",
    "board_card_id": "B-" + clientId,
    "description": "Suite",
    "assigned_deck": "8",
    "assigned_cabin_category": "S1",
    "scheduled_embarkation_date": "2026-04-01",
    "scheduled_disembarkation_date": "2026-04-05",
    "actual_embarkation_date": "2026-04-01",
    "actual_embarkation_time": "1970-01-01T16:30:00",
    "actual_disembarkation_date": (),
    "actual_disembarkation_time": "1970-01-01T08:00:00",
    "emb_port_code": "AAA",
    "disemb_port_code": "BBB",
    "defaultDescription": "Port A"
};

function sampleRows() returns json[] {
    map<json> second = guestRow("R2", "1001", "C-ERR", "8002");
    second["phone_number"] = "0501234567";
    second["is_primary_document"] = ();
    second["preferred_communication_method"] = "PHONE";
    map<json> third = guestRow("R3", "1002", "C3", "9001");
    third["reservation_status_id"] = "CHECKED_OUT";
    third["cruise_product"] = "";
    third["scheduled_embarkation_date"] = ();
    third["is_primary_document"] = "0";
    return [guestRow("R1", "1001", "C1", "8001"), second, third];
}

function sampleRevenue() returns json[] => [
    {"payer_id": "R1", "credit_total": 10, "debit_total": 250, "current_balance": 240},
    {"payer_id": "R9", "credit_total": 1, "debit_total": 1, "current_balance": 0}
];

function sampleTransactions() returns json[] => [
    {"id": "T1", "buyerAccountId": "R1", "profile_id": "P-C1", "businessDate": "2026-04-02", "currencyCode": "SAR",
        "mainDepartmentDescription": "Bar", "settlementAmount": 40, "shipName": "Ship One"},
    {"id": "T2", "buyerAccountId": "R1", "profile_id": "P-C1", "businessDate": "2026-04-03", "currencyCode": "SAR"},
    {"id": "T3", "buyerAccountId": "R3", "profile_id": "P-C3", "businessDate": "2026-04-03", "currencyCode": "SAR"}
];

function sampleItems() returns json[] => [
    {"id": "I1", "posting_id": "T1", "articleDescription": "Juice", "subDepartmentAmount": 15, "postingCount": 1},
    {"id": "I-BAD", "posting_id": "T1", "articleDescription": "Tea", "subDepartmentAmount": 25, "postingCount": 2},
    {"id": "", "posting_id": "T2", "articleDescription": "no id, left out"},
    {"id": "I3", "posting_id": "T3", "articleDescription": "Water", "subDepartmentAmount": 5, "postingCount": 1}
];

function sampleBlock() returns Block {
    json[] rows = attach(sampleRows(), sampleRevenue(), sampleTransactions(), sampleItems());
    return {
        rows,
        correlationId: "run-1",
        jobName: "delta",
        reservationData: [
            {"status": "success", "details": {"id": "Z-RES-1"}},
            {"code": "DUPLICATE_DATA", "status": "error", "details": {"duplicate_record": {"id": "Z-RES-1"}, "id": "Z-x"}},
            {"status": "success", "details": {"id": "Z-RES-2"}}
        ],
        guestAnswers: [
            {"status": "success", "zohoId": "G-C1"},
            {"status": "error", "message": "guest 'refused'", "errorCode": 422},
            {"status": "success", "zohoId": "G-C3"}
        ],
        crmVoyages: [{"Arrival_Date": "2026-04-05", "Departure_Date": "2026-04-01", "Package_Key": "PKG-CRM-1"}]
    };
}

// ---------------------------------------------------------------- time slices

final time:Utc & readonly NOW = [1768039200, 0d]; // 2026-01-10T10:00:00Z

@test:Config {}
function firstDeltaSliceFollowsTheClock() returns error? {
    Window w = check nextWindow({mode: "delta"}, {}, NOW);
    test:assertEquals(w, {'from: "2026-01-10T09:55:00Z", to: "2026-01-10T10:02:00Z"});
}

@test:Config {}
function deltaSliceCatchesUpInTenMinuteSteps() returns error? {
    Window w = check nextWindow({mode: "delta"}, {"lastupdated": "\"2026-01-10T09:00:00Z\""}, NOW);
    test:assertEquals(w, {'from: "2026-01-10T08:57:00Z", to: "2026-01-10T09:10:00Z"});
}

@test:Config {}
function deltaSliceNeverRunsAheadOfTheClock() returns error? {
    Window w = check nextWindow({mode: "delta"}, {"lastupdated": "2026-01-10T10:01:00Z"}, NOW);
    test:assertEquals(w, {'from: "2026-01-10T09:55:00Z", to: "2026-01-10T10:02:00Z"});
}

@test:Config {}
function fixedRangeWalksToItsEnd() returns error? {
    SyncSettings sync = {mode: "delta1", fromDate: "2025-12-19T11:00:00Z", toDate: "2025-12-22T14:00:00Z", windowDays: 1};
    test:assertEquals(check nextWindow(sync, {}, NOW), {'from: "2025-12-19T11:00:00Z", to: "2025-12-20T11:00:00Z"});
    test:assertEquals(check nextWindow(sync, {"lastupdated": "2025-12-22T11:00:00Z"}, NOW),
            {'from: "2025-12-22T11:00:00Z", to: "2025-12-22T14:00:00Z"});
    test:assertEquals(check nextWindow(sync, {"lastupdated": "2025-12-22T14:00:00Z"}, NOW),
            {'from: "2025-12-22T14:00:00Z", to: "2025-12-22T14:00:00Z"});
}

@test:Config {}
function aSliceChosenBeforeTheFirstFinishIsUsedAgain() returns error? {
    map<string> state = {"currentDate": "{\"from\":\"2026-01-01T00:00:00Z\",\"to\":\"2026-01-01T00:07:00Z\"}"};
    test:assertEquals(check nextWindow({mode: "delta"}, state, NOW),
            {'from: "2026-01-01T00:00:00Z", to: "2026-01-01T00:07:00Z"});
}

@test:Config {}
function fixedRangeWithoutDatesIsAnError() {
    test:assertTrue(nextWindow({mode: "full"}, {}, NOW) is error);
}

@test:Config {}
function queryTimesAreWrittenForTheDatabase() {
    test:assertEquals(queryTime("2026-01-10T09:55:00Z"), "2026-01-10 09:55:00");
}

// ---------------------------------------------------------------- read phase

@test:Config {}
function queriesCarryTheirValues() {
    string changed = changedBookingsQuery("('11111')", "2026-01-10 09:55:00", "2026-01-10 10:02:00");
    test:assertTrue(changed.includes("('11111')") && changed.includes("2026-01-10 09:55:00")
            && changed.includes("2026-01-10 10:02:00"));
    test:assertTrue(reservationRowsQuery("'1001','1002'").includes("'1001','1002'"));
    test:assertTrue(revenueQuery("'R1'").includes("'R1'"));
    test:assertTrue(transactionsQuery("'R1'").includes("'R1'"));
    test:assertTrue(postingItemsQuery("'T1'").includes("'T1'"));
    foreach string q in [changed, reservationRowsQuery("''"), revenueQuery("''"), transactionsQuery("''"), postingItemsQuery("''")] {
        string lower = q.trim().toLowerAscii();
        test:assertTrue(lower.startsWith("select") || lower.startsWith("with"), "only reading statements are run");
        test:assertTrue(re `(^|[^a-z_])(insert|update|delete|drop|alter|truncate|create|replace|call|merge)([^a-z_]|$)`.find(lower) is (),
                "only reading statements are run");
    }
}

@test:Config {}
function sqlListsAreQuoted() {
    test:assertEquals(sqlList(["1001", 1002, ()]), "'1001','1002'");
    test:assertEquals(sqlList([]), "''");
}

@test:Config {}
function bookingNumbersThatAreNotDigitsAreReported() {
    [json[], json[]] [good, bad] = splitBookings([{"booking_number": "1001"}, {"booking_number": "AB12"},
        {"booking_number": 1002}, {"booking_number": ()}]);
    test:assertEquals(good, [{"booking_number": "1001"}, {"booking_number": 1002}]);
    map<json>[] rows = invalidBookingRows(bad, "run-1", "delta");
    test:assertEquals(rows.length(), 2);
    test:assertEquals(rows[0].keys(), ["correlation_id", "reservation_number", "source_system", "batch_job_name",
        "module_name", "profile_id", "cabin_number", "client_id", "failure_reason", "error_code"]);
    test:assertEquals(rows[0]["failure_reason"], "Invalid booking_number: AB12");
    test:assertEquals(rows[0]["error_code"], 455);
    test:assertEquals(rows[0]["module_name"], "Reservation");
}

@test:Config {}
function revenueAndSpendAreAttachedToTheirGuest() {
    json[] rows = attach(sampleRows(), sampleRevenue(), sampleTransactions(), sampleItems());
    test:assertEquals(items(f(rows[0], "revenue")).length(), 1);
    test:assertEquals(items(f(rows[1], "revenue")).length(), 0);
    test:assertEquals(f(rows[0], "transactions", "id"), ["T1", "T2"]);
    test:assertEquals(f(at(f(rows[0], "transactions"), 0), "items", "id"), ["I1", "I-BAD"]);
    test:assertEquals(f(rows[2], "transactions", "id"), ["T3"]);
}

@test:Config {}
function reservationSearchNamesEveryBookingOnce() {
    test:assertEquals(accountCriteria(sampleRows()), "(Account_Name:in:1001,1002)");
}

@test:Config {}
function differencesBetweenOtalioAndCrmAreReported() {
    json[] accounts = [
        {"Account_Number": "1001", "Reservation_Status": "Booked", "Package_ID": "X|PKG-CRM"},
        {"Account_Number": "1002", "Reservation_Status": "Cancelled", "Package_ID": "PKG-CRM"},
        {"Account_Number": "7777", "Reservation_Status": "Cancelled"}
    ];
    map<json>[] rows = mismatchRows(sampleRows(), accounts, "run-1", "delta");
    // 1001: two guests, package differs (2 rows). 1002: checked out but cancelled (1) and no package in Otalio (1).
    test:assertEquals(rows.length(), 4);
    test:assertEquals(rows[0]["module_name"], "Voyage");
    test:assertEquals(rows[0]["failure_reason"], "Otalio: PKG-OTALIO, CRM: PKG-CRM");
    test:assertEquals(rows[0]["cabin_number"], "");
    test:assertEquals(rows[2]["module_name"], "Reservation");
    test:assertEquals(rows[2]["failure_reason"], "Otalio: CHECKED_OUT, CRM: Cancelled");
    test:assertEquals(rows[2]["cabin_number"], "9001");
    test:assertEquals(rows[3]["failure_reason"], "Otalio: , CRM: PKG-CRM");
    test:assertEquals(rows[0].keys(), ["correlation_id", "reservation_number", "source_system", "batch_job_name",
        "module_name", "profile_id", "cabin_number", "package_name", "client_id", "failure_reason", "error_code"]);
    test:assertEquals(rows[0].keys(), rows[2].keys());
}

// ---------------------------------------------------------------- answers

@test:Config {}
function answersAreLinedUpWithRecords() {
    test:assertEquals(aligned((), 2), [{"status": "error", "message": "No content (204)"},
        {"status": "error", "message": "No content (204)"}]);
    json refusal = {"status": "error", "errorCode": 400, "message": "reservation : Name-bad"};
    test:assertEquals(aligned([refusal], 3), [refusal, refusal, refusal]);
    json ok = {"status": "success", "details": {"id": "Z1"}};
    test:assertEquals(aligned([ok], 2), [ok, ()]);
    test:assertEquals(recordId({"details": {"id": "A", "duplicate_record": {"id": "B"}}}), "B");
    test:assertEquals(recordId(ok), "Z1");
    test:assertEquals(recordId(()), ());
}

@test:Config {}
function errorRowsKeepTheOldColumnOrder() {
    Block b = sampleBlock();
    map<json> row = errorRow(b, b.rows[0], "Spend Transactions", "it's 'bad'", (), 400, {"posting_id": "T1"});
    test:assertEquals(row.keys(), ["reservation_number", "correlation_id", "cabin_number", "source_system", "module_name",
        "package_name", "client_id", "profile_id", "posting_id", "batch_job_name", "failure_reason", "error_code"]);
    test:assertEquals(row["failure_reason"], "it\"s \"bad\"");
    test:assertEquals(row["error_code"], 400);
    test:assertEquals(row["source_system"], "Otalio");
}

// ---------------------------------------------------------------- reservations

@test:Config {}
function reservationsAreWrittenPerGuestRowAndLinkedToTheVoyageOnTheSecondPass() {
    Block b = sampleBlock();
    test:assertEquals(reservationRecords(b)[0], {"Account_Name": "Reservation|1001", "Account_Number": "1001"});
    b.voyageData = [{"status": "success", "details": {"id": "Z-V1"}}, (),
        {"status": "error", "code": "DUPLICATE_DATA", "details": {"duplicate_record": {"id": "Z-V9"}}}];
    json[] second = reservationRecords(b);
    test:assertEquals(second[0], {"Account_Name": "Reservation|1001", "Account_Number": "1001", "Voyage": {"id": "Z-V1"}});
    test:assertEquals(second[1], {"Account_Name": "Reservation|1001", "Account_Number": "1001"});
    test:assertEquals(f(second[2], "Voyage", "id"), "Z-V9");
    test:assertEquals(upsertBody(second, "Account_Name", true).toJsonString().includes("\"trigger\":[\"workflow\"]"), true);
    test:assertEquals(f(upsertBody([], "Name", false), "trigger"), ());
    test:assertEquals(f(upsertBody([], "Name", false), "duplicate_check_fields"), ["Name"]);
}

@test:Config {}
function alreadyThereIsNotARefusal() {
    Block b = sampleBlock();
    test:assertEquals(refusedRows(b, "Reservation", b.reservationData).length(), 0);
    map<json>[] rows = refusedRows(b, "Reservation", [{"status": "error", "errorCode": 400, "message": "reservation : x-y"}]);
    test:assertEquals(rows.length(), 1);
    test:assertEquals(rows[0]["reservation_number"], "1001");
    test:assertEquals(rows[0]["failure_reason"], "reservation : x-y");
    test:assertEquals(rows[0]["module_name"], "Reservation");
}

// ---------------------------------------------------------------- guests

@test:Config {}
function phoneNumbersAreSplitLikeTheOldHelper() {
    test:assertEquals(splitPhone("+966501234567"), {valid: true, countryCode: "966", number: "501234567"});
    test:assertEquals(splitPhone("+44 020 7946 0958"), {valid: true, countryCode: "44", number: "02079460958"});
    test:assertFalse(splitPhone("0501234567").valid, "no country code, no default country");
    test:assertFalse(splitPhone("not a number").valid);
    test:assertFalse(splitPhone("+1").valid);
    test:assertFalse(splitPhone(()).valid);
}

@test:Config {}
function guestsAreSentWithTheOldFieldNames() {
    json[] request = guestRequest(sampleRows());
    test:assertEquals(request.length(), 3);
    json first = request[0];
    test:assertEquals(f(first, "firstName"), "FirstC1");
    test:assertEquals(f(first, "intlCode"), "966");
    test:assertEquals(f(first, "phone"), "501234567");
    test:assertEquals(f(first, "mailingState"), "never read from here");
    test:assertEquals(f(first, "issueDate"), "2020-01-02");
    test:assertEquals(f(first, "expirationDate"), "2030-01-02");
    test:assertEquals(f(first, "isPrimaryDocument"), true);
    test:assertEquals(f(first, "preferredCommunicationEmail"), true);
    test:assertEquals(f(first, "preferredCommunicationPhone"), false);
    test:assertEquals(f(first, "bookingNumber"), "1001");
    json second = request[1];
    test:assertEquals(f(second, "intlCode"), "");
    test:assertEquals(f(second, "phone"), "");
    test:assertFalse((<map<json>>second).hasKey("isPrimaryDocument"));
    test:assertEquals(f(second, "preferredCommunicationPhone"), true);
    test:assertEquals(f(request[2], "isPrimaryDocument"), false);
}

@test:Config {}
function refusedGuestsAreReported() {
    Block b = sampleBlock();
    map<json>[] rows = guestErrors(b);
    test:assertEquals(rows.length(), 1);
    test:assertEquals(rows[0]["module_name"], "Guest");
    test:assertEquals(rows[0]["client_id"], "C-ERR");
    test:assertEquals(rows[0]["failure_reason"], "guest \"refused\"");
    test:assertEquals(rows[0]["error_code"], 422);
    json[] whole = guestRefusal({status: 502, unreadable: true, failure: "BAD_GATEWAY"}, 3);
    test:assertEquals(whole.length(), 3);
    test:assertEquals(f(whole[0], "errorCode"), 500);
    json[] named = guestRefusal({status: 400, body: {"message": "bad", "details": {"api_name": "Email"}}, failure: "HTTP 400"}, 1);
    test:assertEquals(f(named[0], "message"), "Email-bad");
}

// ---------------------------------------------------------------- links

@test:Config {}
function linksAreCreatedKeptOrSwitchedOff() {
    Block b = sampleBlock();
    test:assertEquals(reservationIds(b), ["Z-RES-1", "Z-x", "Z-RES-2"]);
    json[] existing = [
        {"id": "L-1", "Reservation_Names": {"id": "Z-RES-1"}, "Guest_Names": {"id": "G-C1"}},
        {"id": "L-2", "Reservation_Names": {"id": "Z-RES-1"}, "Guest_Names": {"id": "G-GONE"}}
    ];
    LinkingPlan plan = linkingPlan(b, existing);
    // G-C3 on Z-RES-2 is new; the refused guest (row 2) gets no link.
    test:assertEquals(plan.creates, [{"data": [{"Reservation_Names": {"id": "Z-RES-2"}, "Guest_Names": {"id": "G-C3"},
        "Reservation_Status_Otalio": "CHECKED_OUT", "Active_Inactive": "Active", "Modified_By_System": "Otalio"}]}]);
    test:assertEquals(plan.updates.length(), 2);
    test:assertEquals(f(plan.updates[0], "data", "id"), ["L-1"]);
    test:assertEquals(f(plan.updates[0], "data", "Active_Inactive"), ["Active"]);
    test:assertEquals(plan.updates[1], {"data": [{"Reservation_Names": {"id": "Z-RES-1"}, "Guest_Names": {"id": "G-GONE"},
        "Active_Inactive": "Inactive", "Modified_By_System": "Otalio", "id": "L-2"}]});
    test:assertEquals(anyOf("Reservation_Names:equals", ["a", "b"]), "((Reservation_Names:equals:a) or (Reservation_Names:equals:b))");
}

// ---------------------------------------------------------------- voyage look-up

@test:Config {}
function voyagesAreLookedUpByTheSailingDates() {
    json[] queries = voyageDateQueries(sampleRows());
    test:assertEquals(queries.length(), 1, "two rows share one pair of dates, the third has no dates");
    test:assertEquals(f(queries[0], "select_query"),
            "select Arrival_Date_and_Time,Departure_Date_and_Time,Package_Key from Voyages where "
            + "(Arrival_Date_and_Time between '2026-04-05T00:00:00-00:00' and '2026-04-05T23:59:59-00:00' AND "
            + "Departure_Date_and_Time between '2026-04-01T00:00:00-00:00' and '2026-04-01T23:59:59-00:00')"
            + " and Package_Key is not null group by Package_Key,Departure_Date_and_Time,Arrival_Date_and_Time");
    test:assertEquals(buildWhere(["a", "b", "c"]), "(a OR ((b OR (c))))");
    json[] many = from int i in 10 ..< 23
        select {"scheduled_embarkation_date": "2026-04-" + i.toString(), "scheduled_disembarkation_date": "2026-05-" + i.toString()};
    test:assertEquals(voyageDateQueries(many).length(), 2, "12 pairs of dates per query");
}

@test:Config {}
function thePackageComesFromTheCrmWhenExactlyOneVoyageSailsOnTheDates() {
    json[] found = crmVoyages([
        {"Arrival_Date_and_Time": "2026-04-05T08:00:00+03:00", "Departure_Date_and_Time": "2026-04-01T16:00:00+03:00", "Package_Key": "PKG-CRM-1"},
        {"Arrival_Date_and_Time": "2026-04-05T09:00:00+03:00", "Departure_Date_and_Time": "2026-04-01T17:00:00+03:00", "Package_Key": "PKG-CRM-1"},
        {"Arrival_Date_and_Time": "2026-04-05T09:00:00+03:00", "Departure_Date_and_Time": (), "Package_Key": "PKG-X"}
    ]);
    test:assertEquals(found, [{"Arrival_Date": "2026-04-05", "Departure_Date": "2026-04-01", "Package_Key": "PKG-CRM-1"}]);
    Block b = sampleBlock();
    test:assertEquals(packageKey(b, b.rows[0]), "PKG-CRM-1");
    test:assertEquals(packageKey(b, b.rows[2]), "", "no dates: the package named in Otalio");
    b.crmVoyages.push({"Arrival_Date": "2026-04-05", "Departure_Date": "2026-04-01", "Package_Key": "PKG-CRM-2"});
    test:assertEquals(packageKey(b, b.rows[0]), "PKG-OTALIO", "two voyages on the dates: the package named in Otalio");
}

// ---------------------------------------------------------------- spend

@test:Config {}
function spendTransactionsCarryTheirLinks() {
    Block b = sampleBlock();
    json[] records = spendRecords(b, 0);
    test:assertEquals(records.length(), 2);
    test:assertEquals(f(records[0], "Name"), "1001|C1|T1");
    test:assertEquals(f(records[0], "Voyage"), "PKG-CRM-1");
    test:assertEquals(f(records[0], "Guest_Seaware_Info", "id"), "G-C1");
    test:assertEquals(f(records[0], "Reservation_Seaware_Info", "id"), "Z-RES-1");
    test:assertEquals(f(records[0], "Main_Department"), "Bar");
    test:assertEquals(f(records[0], "Posting_ID"), "T1");
    test:assertEquals(spendRecords(b, 1).length(), 0);
    b.spendAnswers = [[{"status": "success", "details": {"id": "Z-T1"}}, {"status": "error", "message": "no", "errorCode": 422}],
        [], [{"status": "success", "details": {"id": "Z-T3"}}]];
    map<json>[] rows = spendErrors(b);
    test:assertEquals(rows.length(), 1);
    test:assertEquals(rows[0]["posting_id"], "T2");
    test:assertEquals(rows[0]["module_name"], "Spend Transactions");
    test:assertEquals(rows[0]["error_code"], 422);
}

@test:Config {}
function spendItemsAreLinkedToTheirOwnTransaction() {
    Block b = sampleBlock();
    b.spendAnswers = [[{"status": "success", "details": {"id": "Z-T1"}}, {"status": "success", "details": {"id": "Z-T2"}}],
        [], [{"status": "success", "details": {"id": "Z-T3"}}]];
    ItemGroup[] groups = spendItemGroups(b);
    test:assertEquals(groups.length(), 2, "the transaction whose only item has no id is skipped");
    test:assertEquals(f(groups[0].records, "Name"), ["I1", "I-BAD"]);
    test:assertEquals(f(groups[0].records[0], "Spend_Transaction", "id"), "Z-T1");
    test:assertEquals(f(groups[0].records[0], "Amount"), 15);
    test:assertEquals(f(groups[1].records[0], "Spend_Transaction", "id"), "Z-T3");
    map<json>[] rows = spendItemErrors(b, groups[0], [{"status": "success"}, {"status": "error", "message": "no"}]);
    test:assertEquals(rows.length(), 1);
    test:assertEquals(rows[0]["article_id"], "I-BAD");
    test:assertEquals(rows[0]["posting_id"], "T1");
    test:assertEquals(rows[0]["module_name"], "Spend Articles");
    test:assertEquals(rows[0].keys(), ["reservation_number", "correlation_id", "cabin_number", "source_system", "module_name",
        "package_name", "client_id", "profile_id", "posting_id", "article_id", "batch_job_name", "failure_reason", "error_code"]);
}

// ---------------------------------------------------------------- cabins

@test:Config {}
function cabinsAreWrittenPerBookingAndOldOnesSwitchedOff() {
    Block b = sampleBlock();
    test:assertEquals(cabinBookings(b.rows), ["1001", "1002"]);
    Group[] groups = cabinGroups(b, [{"id": "Z-OLD", "Name": "1001|C0|7000"}, {"id": "Z-SAME", "Name": "1001|C1|8001"}]);
    test:assertEquals(groups.length(), 2);
    test:assertEquals(groups[0].key, "1001");
    test:assertEquals(f(groups[0].records, "Name"), ["1001|C1|8001", "1001|C-ERR|8002", "1001|C0|7000"]);
    json first = groups[0].records[0];
    test:assertEquals(f(first, "Package_Key"), "PKG-CRM-1");
    test:assertEquals(f(first, "Debit_Total"), 250);
    test:assertEquals(f(first, "Guest_Name", "id"), "G-C1");
    test:assertEquals(f(first, "Reservation", "id"), "Z-RES-1");
    test:assertEquals(f(first, "Active_Inactive"), "Active");
    test:assertEquals(f(groups[0].records[1], "Credit_Total"), ());
    test:assertEquals(groups[0].records[2], {"Name": "1001|C0|7000", "Modified_By_System": "Otalio", "Active_Inactive": "Inactive"});
    json ok = {"status": "success"};
    test:assertEquals(cabinErrors(b, groups, [[ok, ok, ok], [ok]]).length(), 0);
    map<json>[] rows = cabinErrors(b, groups, [[ok, {"status": "error", "message": "it's full", "errorCode": 409}, ok], [ok]]);
    test:assertEquals(rows.length(), 1);
    test:assertEquals(rows[0]["reservation_number"], "1001");
    test:assertEquals(rows[0]["client_id"], "C-ERR");
    test:assertEquals(rows[0]["cabin_number"], "8002");
    test:assertEquals(rows[0]["failure_reason"], "it\"s full");
    test:assertEquals(rows[0]["error_code"], 409);
}

// ---------------------------------------------------------------- voyages

@test:Config {}
function voyagesAreWrittenPerGuestRow() {
    Block b = sampleBlock();
    json[] records = voyageRecords(b);
    test:assertEquals(records.length(), 3);
    test:assertEquals(f(records[0], "Name"), "PKG-CRM-1");
    test:assertEquals(f(records[0], "Package_Key"), "PKG-CRM-1");
    test:assertEquals(f(records[0], "Actual_Embarkation_Time"), "2026-04-01T16:30:00");
    test:assertEquals(f(records[0], "Actual_Disembarkation_Time"), (), "no date: no time");
    test:assertEquals(f(records[0], "Port_Code_Embarkation"), "AAA");
    test:assertEquals(f(records[0], "Port_Name_Disembarkation"), "Port A");
    test:assertEquals(f(records[2], "Name"), "");
}

// ---------------------------------------------------------------- database rows

@test:Config {}
function databaseValuesBecomeTheTextTheOldJobSaw() {
    record {} row = {
        "booking_number": "1001",
        "amount": 12.5d,
        "born": {year: 1990, month: 2, day: 3},
        "clock": {hour: 8, minute: 5, second: 3.0d},
        "changed": {year: 2026, month: 4, day: 1, hour: 16, minute: 30, second: 0.0d},
        "seen": <time:Utc>[1768039200, 0d],
        "nothing": ()
    };
    test:assertEquals(rowJson(row), {
        "booking_number": "1001",
        "amount": 12.5d,
        "born": "1990-02-03",
        "clock": "08:05:03",
        "changed": "2026-04-01T16:30:00",
        "seen": "2026-01-10T10:00:00",
        "nothing": ()
    });
}

// ---------------------------------------------------------------- one whole run against the local stand-in

isolated class FakeRows {
    *RowSource;
    private final readonly & json[][] answers;
    private final string[] queries = [];

    isolated function init(json[][] answers) {
        self.answers = answers.cloneReadOnly();
    }

    public isolated function rows(string query) returns json[]|error {
        int n;
        lock {
            self.queries.push(query);
            n = self.queries.length() - 1;
        }
        return n < self.answers.length() ? self.answers[n].clone() : [];
    }

    isolated function seen() returns string[] {
        lock {
            return self.queries.clone();
        }
    }
}

// Runs only when the stand-in is up (SYNC_DOUBLE_URL); never against a real system.
@test:Config {}
function aWholeRunAgainstTheStandIn() returns error? {
    string base = os:getEnv("SYNC_DOUBLE_URL");
    if base == "" {
        return;
    }
    SyncSettings sync = {mode: "delta", retryWaitSeconds: 0, errorTable: "stand_in_error_log", skipBookingNumbers: "('11111')"};
    Backend zoho = check new ("CRM system service", {url: base + "/otalio/zoho"}, sync);
    Backend guests = check new ("guest service", {url: base + "/otalio/guest"}, sync);
    Backend db = check new ("database system service", {url: base + "/otalio/db"}, sync);
    StateStore state = check new ({enabled: false, host: "", port: 6379}, "test:");
    FakeRows fake = new ([
        [{"booking_number": "1001"}, {"booking_number": "AB12"}, {"booking_number": "1002"}],
        sampleRows(),
        sampleRevenue(),
        sampleTransactions(),
        sampleItems()
    ]);
    OtalioSync job = new (state, fake, zoho, guests, db, check new ErrorMail({}), sync, {});

    test:assertEquals(job.run(), "done: 2 booking(s), 3 guest row(s), 0 failed block(s)");
    string[] queries = fake.seen();
    test:assertEquals(queries.length(), 5);
    test:assertTrue(queries[0].includes("('11111')"));
    test:assertEquals(queries[1], reservationRowsQuery("'1001','1002'"));
    test:assertEquals(queries[2], revenueQuery("'R1','R2','R3'"));
    test:assertEquals(queries[3], transactionsQuery("'R1','R2','R3'"));
    test:assertEquals(queries[4], postingItemsQuery("'T1','T2','T3'"));
    map<string> saved = check state.all(STATE_KEYS);
    test:assertEquals(saved["otalioStatus"], "Completed");
    test:assertEquals(saved["batchStatus"], "Completed");
    json slice = check (saved["currentDate"] ?: "").fromJsonString();
    test:assertEquals(saved["lastupdated"], f(slice, "to"));

    // Next run: nothing changed. The slice still moves on.
    test:assertEquals(job.run(), "done: 0 booking(s), 0 guest row(s), 0 failed block(s)");
    test:assertEquals(fake.seen().length(), 6);

    // A run that was cut off leaves "InProgress" behind: the job waits until that is cleared.
    check state.put("batchStatus", "InProgress");
    test:assertEquals(job.run(), "skipped: earlier run marked in progress");
    test:assertEquals(fake.seen().length(), 6);
    check state.clear(STATE_KEYS);
    test:assertEquals(job.run(), "done: 0 booking(s), 0 guest row(s), 0 failed block(s)");
}

@test:Config {}
function aFailedReadDoesNotLeaveTheJobBlocked() returns error? {
    string base = os:getEnv("SYNC_DOUBLE_URL");
    if base == "" {
        return;
    }
    SyncSettings sync = {mode: "full", retryWaitSeconds: 0};
    Backend zoho = check new ("CRM system service", {url: base + "/otalio/zoho"}, sync);
    StateStore state = check new ({enabled: false, host: "", port: 6379}, "test2:");
    OtalioSync job = new (state, new FakeRows([]), zoho, zoho, (), check new ErrorMail({}), sync, {});
    test:assertTrue(job.run().startsWith("failed: "));
    test:assertEquals((check state.all(STATE_KEYS))["otalioStatus"], "Completed");
}
