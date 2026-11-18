import ballerina/os;
import ballerina/test;
import ballerina/time;

// ---------------------------------------------------------------- sample data (made up)

function sampleEdge(string key) returns json => {
    "cursor": "c-" + key,
    "node": {
        "key": key,
        "id": "Reservation|" + key,
        "sourceCode": "WEB",
        "version": 3,
        "guestCount": 2,
        "status": {"name": "Booked"},
        "currency": {"key": "SAR"},
        "confirmationDate": "2026-01-02T10:00:00",
        "initialDate": "2026-01-01T09:00:00",
        "lastUpdated": "2026-01-03T11:00:00",
        "originalInitialDate": "",
        "agency": {
            "key": "AG1",
            "isInternal": true,
            "name": "Agency One",
            "type": {"key": "TA"},
            "phones": [{"intlCode": "900", "number": "5550001"}],
            "addresses": [
                {"type": {"key": "POSTAL"}, "line1": "P1", "line2": "P2", "city": "Port City", "country": {"name": "Atlantis"}},
                {"type": {"key": "EMAIL"}, "line1": "E1", "city": "Mail City", "country": {"name": "Atlantis"}}
            ]
        },
        "commissions": [{"code": "C1"}, {"code": "C2"}],
        "secondaryAgent": {"key": "A7", "firstName": "Sam", "lastName": "Lee", "email": "agent@example.test",
            "phones": [{"intlCode": "44", "number": "700"}]},
        "invoiceTotals": {"invoiceTotal": 1500, "currentDue": {"amount": 200, "date": "2026-03-01T00:00:00"}},
        "group": {"key": "G1", "name": "Group One", "agent": {"key": "GA1", "email": "group@example.test"}},
        "lastInvoice": {"invoiceId": 9001},
        "coupons": [{"coupon": {"key": "CP1"}}],
        "invoice": [{"priceArea": "FARE", "promotion": {"key": "PR1", "code": "PR1", "type": "DISCOUNT"}, "amount": 10}],
        "paymentSchedule": [{"paid": true, "paidAmount": 100, "dueDate": "2026-02-01T00:00:00", "dueType": "DEPOSIT"}],
        "transactions": [{"amount": 100, "dateTime": "2026-01-05T09:00:00", "form": {"key": "CARD"}, "priceToBaseCurrencyRate": 1}],
        "guests": [
            {
                "age": 34,
                "client": {
                    "key": "CL1", "firstName": "Ann", "lastName": "Ray", "gender": "F", "eMail": "ann@example.test",
                    "title": {"key": "MS"}, "birthday": "1991-05-06", "middleName": "B",
                    "citizenship": {"key": "AT", "name": "Atlantis"},
                    "countryOfResidence": {"key": "AT", "name": "Atlantis"},
                    "countryOfBirth": {"name": "Atlantis"},
                    "language": {"key": "EN", "name": "English"},
                    "phones": [{"intlCode": 900, "number": "5551001"}],
                    "household": {"key": "H1", "addresses": [{"city": "Port City"}]}
                },
                "calculatedFields": {"pointsInfo": {"balance": {"clubAccountNumber": "CLUB1"}}},
                "addons": [
                    {"addon": {"key": "AIR-F", "id": "AD1", "category": {"key": "AIR"}, "type": {"key": "SERVICE"}},
                        "price": 50, "quantity": 2, "isSpecialRequest": false}
                ],
                "shorex": [{"price": 20}, {"price": 5}],
                "voyages": [
                    {
                        "pkg": {"key": "PKG1", "id": "P-1", "sailDays": 4, "type": {"name": "Cruise", "comments": "4 nights"},
                            "destinations": [{"id": "D1", "key": "RS", "name": "Red Sea", "comments": "Red Sea"}]},
                        "ship": {"key": "SHIP1"},
                        "sail": {
                            "from": {"dateTime": "2026-04-01T16:00:00", "port": {"id": "1", "key": "JED", "name": "Jeddah"}},
                            "to": {"dateTime": "2026-04-05T08:00:00", "port": {"id": "2", "key": "YNB", "name": "Yanbu"}}
                        },
                        "cabinChain": [{"cabin": {"number": "8001", "category": {"comments": "Suite"}}}],
                        "promotions": [{"promotion": {"code": "PR1"}}]
                    }
                ]
            },
            {
                "client": {"key": "CL2", "firstName": "Bo", "lastName": "Ray", "phones": []},
                "voyages": [{"pkg": {"key": "PKG1"}, "cabinChain": []}]
            }
        ]
    }
};

function crmOk(string... ids) returns json =>
    {"data": from string id in ids select {"code": "SUCCESS", "status": "success", "details": {"id": id}}};

function sampleChunk() returns Chunk => {edges: [sampleEdge("R100")], correlationId: "run-1", jobName: "delta"};

function writtenChunk() returns Chunk {
    Chunk c = sampleChunk();
    c.reservationAnswer = crmOk("Z-R100");
    c.contactAnswers = [[{"zohoId": "G-CL1", "status": "success"}, {"zohoId": "G-CL2", "status": "success"}]];
    return c;
}

function first(json request) returns json => at(f(request, "data"), 0);

// ---------------------------------------------------------------- reading JSON like the old scripts

@test:Config {}
function fieldPathsReadThroughLists() {
    json v = {"a": [{"b": {"c": 1}}, {"b": {}}, {"b": {"c": 3}}]};
    test:assertEquals(f(v, "a", "b", "c"), [1, 3]);
    test:assertEquals(f(v, "a", "x"), ());
    test:assertEquals(at(f(v, "a", "b", "c"), -1), 3);
    test:assertEquals(at(5, 0), ());
}

@test:Config {}
function emptinessAndText() {
    test:assertTrue(blank(()) && blank("") && blank([]) && blank({}));
    test:assertFalse(blank(0) || blank(false) || blank("x"));
    test:assertEquals(text(12), "12");
    test:assertEquals(textOr((), "-"), "-");
    test:assertEquals(dateOnly("2026-03-01T00:00:00"), "2026-03-01");
    test:assertEquals(dateOnly(""), ());
}

@test:Config {}
function listHelpers() {
    json v = {"g": [{"addons": [{"price": 1}, {"price": 2}]}, {"addons": [{"price": 4}]}, {}]};
    test:assertEquals(sum(f(flat(deep(v, "addons")), "price")), 7);
    test:assertEquals(sum(()), ());
    test:assertEquals(chunks([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]]);
    test:assertEquals(unique([1, 2, 1, {"a": 1}, {"a": 1}]), [1, 2, {"a": 1}]);
    test:assertEquals(items(()), []);
    test:assertEquals(items("x"), ["x"]);
}

// ---------------------------------------------------------------- the slice of time

final time:Utc NOW = checkpanic time:utcFromString("2026-01-10T12:00:00Z");

@test:Config {}
function deltaStartsAroundNow() returns error? {
    test:assertEquals(check nextWindow({}, {}, NOW),
            {'from: "2026-01-10T11:55:00Z", to: "2026-01-10T12:02:00Z", cursor: "0"});
}

@test:Config {}
function deltaContinuesFromLastSlice() returns error? {
    map<string> state = {"lastupdated": "\"2026-01-10T11:00:00Z\"", "seawareNextPage": "false"};
    test:assertEquals(check nextWindow({}, state, NOW),
            {'from: "2026-01-10T10:59:00Z", to: "2026-01-10T11:10:00Z", cursor: "0"});
}

@test:Config {}
function deltaNeverRunsAheadOfTheClock() returns error? {
    map<string> state = {"lastupdated": "2026-01-10T12:02:00Z", "seawareNextPage": ""};
    test:assertEquals(check nextWindow({}, state, NOW),
            {'from: "2026-01-10T11:55:00Z", to: "2026-01-10T12:02:00Z", cursor: "0"});
}

final readonly & SyncSettings FIXED = {mode: "delta1", fromDate: "2026-09-16T10:30:00Z", toDate: "2026-09-20T12:00:00Z"};

@test:Config {}
function fixedRangeWalksInSteps() returns error? {
    test:assertEquals(check nextWindow(FIXED, {}, NOW),
            {'from: "2026-09-16T10:30:00Z", to: "2026-09-18T10:30:00Z", cursor: "0"});
    test:assertEquals(check nextWindow(FIXED, {"lastupdated": "2026-09-18T10:30:00Z", "seawareNextPage": "false"}, NOW),
            {'from: "2026-09-18T10:30:00Z", to: "2026-09-20T10:30:00Z", cursor: "0"});
}

@test:Config {}
function fixedRangeStopsAtTheEndDate() returns error? {
    test:assertEquals(check nextWindow(FIXED, {"lastupdated": "2026-09-20T10:30:00Z", "seawareNextPage": "false"}, NOW),
            {'from: "2026-09-20T10:30:00Z", to: "2026-09-20T12:00:00Z", cursor: "0"});
    test:assertEquals(check nextWindow(FIXED, {"lastupdated": "2026-09-20T12:00:00Z", "seawareNextPage": "false"}, NOW),
            {'from: "2026-09-20T12:00:00Z", to: "2026-09-20T12:00:00Z", cursor: "0"});
}

@test:Config {}
function unfinishedSliceIsRepeatedFromItsPage() returns error? {
    map<string> state = {
        "lastupdated": "2026-09-18T10:30:00Z",
        "seawareCursor": "abc",
        "seawareNextPage": "true",
        "currentDate": "{\"from\":\"2026-09-16T10:30:00Z\", \"to\":\"2026-09-18T10:30:00Z\"}"
    };
    test:assertEquals(check nextWindow(FIXED, state, NOW),
            {'from: "2026-09-16T10:30:00Z", to: "2026-09-18T10:30:00Z", cursor: "abc"});
}

@test:Config {}
function fixedRangeNeedsItsDates() {
    test:assertTrue(nextWindow({mode: "full"}, {}, NOW) is error);
}

// ---------------------------------------------------------------- Seaware requests

@test:Config {}
function reservationsQueryCarriesSliceAndPage() {
    json firstPage = reservationsBody({'from: "A", to: "B", cursor: "0"}, 100);
    string query = textOr(f(firstPage, "query"), "");
    test:assertTrue(query.startsWith("query Reservations {\n reservations(\n params: {updatedAt: {from: \"A\", to: \"B\" } } first : 100\nlast : 0\n) { edges {"));
    test:assertTrue(query.includes("pageInfo"));
    string next = textOr(f(reservationsBody({'from: "A", to: "B", cursor: "xyz"}, 50), "query"), "");
    test:assertTrue(next.includes("first : 50\nafter : xyz\n"));
}

@test:Config {}
function signInRequestNamesTheAccount() {
    string query = textOr(f(loginBody({username: "u1", password: "p1"}), "query"), "");
    test:assertTrue(query.startsWith("mutation Login { login(role: ResAgent, login: \"u1\", password: \"p1\", totalTimeout: \"PT2H\""));
}

// ---------------------------------------------------------------- reservations

@test:Config {}
function reservationFirstPassHasNoLinks() {
    json request = reservationRequest(sampleChunk());
    json rec = first(request);
    test:assertEquals(f(request, "duplicate_check_fields"), ["Account_Name"]);
    test:assertEquals(f(request, "trigger"), ["workflow"]);
    test:assertEquals(f(rec, "Account_Name"), "Reservation|R100");
    test:assertEquals(f(rec, "Account_Number"), "R100");
    test:assertEquals(f(rec, "Agency_Phone"), "9005550001");
    test:assertEquals(f(rec, "Address_Type"), "EMAIL");
    test:assertEquals(f(rec, "Address_Line_1"), "E1");
    test:assertEquals(f(rec, "Address_Line_2"), "P2");
    test:assertEquals(f(rec, "Agency_City"), "Mail City");
    test:assertEquals(f(rec, "Commission_Code"), "C1,C2");
    test:assertEquals(f(rec, "Agent_Phone"), "44700");
    test:assertEquals(f(rec, "External_System"), false);
    test:assertEquals(f(rec, "Price_Addons"), 50);
    test:assertEquals(f(rec, "Price_Shorex"), 25);
    test:assertEquals(f(rec, "Due_Date"), "2026-03-01");
    test:assertEquals(f(rec, "Reservation_Version"), "3");
    test:assertEquals(f(rec, "Reservation_Original_Initial_Date"), ());
    test:assertEquals(f(rec, "Flight_Cruise_Enabled"), true);
    test:assertEquals(f(rec, "Source_System"), "Seaware");
    test:assertEquals(f(rec, "Reservation_Contact"), ());
    test:assertEquals(f(rec, "Cabin_Info"), ());
    test:assertEquals(f(rec, "Voyage"), ());
}

@test:Config {}
function reservationLastPassLinksWhatWasWritten() {
    Chunk c = writtenChunk();
    c.groupAnswer = crmOk("Z-G1");
    c.invoiceAnswer = crmOk("Z-INV");
    c.voyageAnswers = [crmOk("Z-VOY")];
    c.cabinCorrelation = [
        {"reservationNumber": "R100", "cabins": [
            {"reservationNumber": "R100", "name": "R100|CL1|8001", "guestId": "G-CL1", "activeInactive": "Active", "zohoId": "Z-CAB", "status": "success"},
            {"reservationNumber": "R100", "name": "R100|CL1|7000", "guestId": "G-CL1", "activeInactive": "Inactive", "zohoId": "Z-OLD", "status": "success"}
        ]}
    ];
    json rec = first(reservationRequest(c));
    test:assertEquals(f(rec, "Reservation_Contact"), {"id": "G-CL1"});
    test:assertEquals(f(rec, "Cabin_Info"), {"id": "Z-CAB"});
    test:assertEquals(f(rec, "Group_Agency_Name"), {"id": "Z-G1"});
    test:assertEquals(f(rec, "Finance_Name"), {"id": "Z-INV"});
    test:assertEquals(f(rec, "Voyage"), {"id": "Z-VOY"});
}

@test:Config {}
function primaryCabinNeedsExactlyOneMatch() {
    Chunk c = sampleChunk();
    json cabin = {"reservationNumber": "R100", "guestId": "G1", "activeInactive": "Active", "zohoId": "Z1", "status": "success"};
    c.cabinCorrelation = [{"reservationNumber": "R100", "cabins": [cabin, cabin]}];
    test:assertEquals(primaryCabinId(c, "R100", "G1"), ());
    c.cabinCorrelation = [{"reservationNumber": "R100", "cabins": [cabin]}];
    test:assertEquals(primaryCabinId(c, "R100", "G1"), "Z1");
    test:assertEquals(primaryCabinId(c, "R100", ()), ());
}

@test:Config {}
function refusedReservationBecomesAnErrorRow() {
    Chunk c = sampleChunk();
    c.reservationAnswer = {"data": [{"status": "error", "errorCode": 400, "message": "reservation : Currency-it's invalid"}]};
    map<json>[] rows = reservationErrors(c);
    test:assertEquals(rows.length(), 1);
    test:assertEquals(rows[0], {
        "reservation_number": "R100", "correlation_id": "run-1", "cabin_number": "8001", "source_system": "Seaware",
        "module_name": "Reservation", "package_name": "PKG1", "client_id": "CL1", "batch_job_name": "delta",
        "failure_reason": "reservation : Currency-it\"s invalid", "error_code": 400
    });
}

// ---------------------------------------------------------------- guests

@test:Config {}
function guestRequestHasOneEntryPerGuest() {
    json[] request = guestRequest(f(sampleEdge("R100"), "node"));
    test:assertEquals(request.length(), 2);
    test:assertEquals(request[0], {
        "title": "MS", "firstName": "Ann", "lastName": "Ray", "gender": "F", "email": "ann@example.test",
        "nationalityKey": "AT", "nationalityName": "Atlantis", "dateOfBirth": "1991-05-06",
        "countryOfResidenceName": "Atlantis", "countryOfResidenceKey": "AT", "city": "Port City",
        "languageKey": "EN", "languageName": "English", "intlCode": "900", "phone": "5551001", "age": "34",
        "clientId": "CL1", "clubAccount": "CLUB1", "countryOfBirth": "Atlantis", "householdId": "H1",
        "middleName": "B", "mobile": "9005551001", "mailingCity": "Port City", "accountName": "Reservation|R100"
    });
    test:assertEquals(f(request[1], "intlCode"), "");
    test:assertEquals(f(request[1], "mobile"), "");
    test:assertEquals(f(request[1], "age"), ());
}

@test:Config {}
function guestRequestAddsScopeFieldsOnlyWhenAsked() {
    json[] plain = guestRequest(f(sampleEdge("R100"), "node"), false);
    test:assertEquals(plain, guestRequest(f(sampleEdge("R100"), "node")));
    test:assertFalse((<map<json>>plain[0]).hasKey("sourceCode"));
    json[] scoped = guestRequest(f(sampleEdge("R100"), "node"), true);
    test:assertEquals(scoped.length(), 2);
    test:assertEquals(f(scoped[0], "sourceCode"), f(sampleEdge("R100"), "node", "sourceCode"));
    test:assertEquals(f(scoped[1], "agencyName"), f(sampleEdge("R100"), "node", "agency", "name"));
}

@test:Config {}
function guestRefusalAnswersForEveryGuest() {
    json[] unreadable = guestRefusal({status: 502, unreadable: true, failure: "HTTP 502"}, 2);
    test:assertEquals(unreadable, [{"status": "error", "errorCode": 500, "message": "HTTP 502"},
        {"status": "error", "errorCode": 500, "message": "HTTP 502"}]);
    json[] named = guestRefusal({status: 400, body: {"message": "is required", "details": {"api_name": "Email"}}, failure: "HTTP 400"}, 1);
    test:assertEquals(named, [{"status": "error", "errorCode": 400, "message": "Email-is required"}]);
    Chunk c = sampleChunk();
    c.contactAnswers = [[named[0], {"zohoId": "G2", "status": "success"}]];
    map<json>[] rows = guestErrors(c);
    test:assertEquals(rows.length(), 1);
    test:assertEquals(rows[0]["module_name"], "Guest");
    test:assertEquals(rows[0]["client_id"], "CL1");
    test:assertEquals(rows[0]["error_code"], 400);
}

// ---------------------------------------------------------------- links

@test:Config {}
function linksAreCreatedKeptAndSwitchedOff() {
    Chunk c = writtenChunk();
    json[] existing = [
        {"id": "L1", "Reservation_Names": {"id": "Z-R100"}, "Guest_Names": {"id": "G-CL1"}, "Modified_By_System": "Seaware"},
        {"id": "L2", "Reservation_Names": {"id": "Z-R100"}, "Guest_Names": {"id": "G-GONE"}},
        {"id": "L3", "Reservation_Names": {"id": "Z-R100"}, "Guest_Names": {"id": "G-OTHER"}, "Modified_By_System": "Otalio"}
    ];
    LinkingPlan plan = linkingPlan(c, existing);
    test:assertEquals(plan.creates, [
        {"data": [{"Reservation_Names": {"id": "Z-R100"}, "Guest_Names": {"id": "G-CL2"}, "Active_Inactive": "Active", "Modified_By_System": "Seaware"}]}
    ]);
    test:assertEquals(plan.updates, [
        {"data": [
            {"Reservation_Names": {"id": "Z-R100"}, "Guest_Names": {"id": "G-CL1"}, "Active_Inactive": "Active", "Modified_By_System": "Seaware", "id": "L1"},
            {"Reservation_Names": {"id": "Z-R100"}, "Guest_Names": {"id": "G-GONE"}, "Active_Inactive": "Inactive", "Modified_By_System": "Seaware", "id": "L2"}
        ]}
    ]);
    test:assertEquals(reservationIds(c), ["Z-R100"]);
    test:assertEquals(anyOf("Reservation_Names:equals", ["a", "b"]), "((Reservation_Names:equals:a) or (Reservation_Names:equals:b))");
}

@test:Config {}
function noLinksWithoutAWrittenReservation() {
    Chunk c = writtenChunk();
    c.reservationAnswer = {"data": [{"status": "error", "message": "refused"}]};
    LinkingPlan plan = linkingPlan(c, []);
    test:assertEquals(plan.creates.length() + plan.updates.length(), 0);
}

// ---------------------------------------------------------------- cabins and add-ons

@test:Config {}
function ownershipDecidesWhatIsWritten() {
    json[] fresh = [{"Name": "R1|C1|8001", "x": 1}, {"Name": "R1|C2|8002"}, {"Name": "R1|C3|8003"}];
    json[] existing = [
        {"Name": "R1|C1|8001", "Modified_By_System": "Seaware"},
        {"Name": "R1|C2|8002", "Modified_By_System": "Otalio"},
        {"Name": "R1|C9|7000"},
        {"Name": "R1|C8|6000", "Modified_By_System": "Otalio"}
    ];
    test:assertEquals(ownedMerge(fresh, existing), [
        {"Name": "R1|C1|8001", "x": 1, "Modified_By_System": "Seaware", "Active_Inactive": "Active"},
        {"Name": "R1|C3|8003", "Modified_By_System": "Seaware", "Active_Inactive": "Active"},
        {"Name": "R1|C9|7000", "Modified_By_System": "Seaware", "Active_Inactive": "Inactive"}
    ]);
}

@test:Config {}
function cabinsAreGroupedPerReservation() {
    Chunk c = writtenChunk();
    json[] records = cabinRecords(c);
    test:assertEquals(records.length(), 2);
    test:assertEquals(records[0], {
        "Cabin_Number": "8001", "Cabin_Type": "Suite", "Package_Key": "PKG1", "Name": "R100|CL1|8001",
        "Guest_Name": {"id": "G-CL1"}, "Reservation": {"id": "Z-R100"}
    });
    test:assertEquals(f(records[1], "message"), "No cabin assigned");
    Group[] groups = byReservation(ownedMerge(records, []));
    test:assertEquals(groups.length(), 1);
    test:assertEquals(groups[0].key, "R100");
    json[] send = writable(groups[0]);
    test:assertEquals(send.length(), 1);
    test:assertEquals(f(cabinRequest(send), "duplicate_check_fields"), ["Name"]);
    json[] answers = answersFor(groups[0], crmOk("Z-CAB"));
    test:assertEquals(f(answers[0], "details", "id"), "Z-CAB");
    test:assertEquals(f(answers[1], "status"), "error");
    json correlation = cabinCorrelation(groups[0], answers);
    test:assertEquals(at(f(correlation, "cabins"), 0), {
        "reservationNumber": "R100", "name": "R100|CL1|8001", "guestId": "G-CL1", "activeInactive": "Active",
        "zohoId": "Z-CAB", "status": "success"
    });
    map<json>[] rows = cabinErrors(c, groups[0], answers);
    test:assertEquals(rows.length(), 1);
    test:assertEquals(rows[0]["client_id"], "CL2");
    test:assertEquals(rows[0]["failure_reason"], "No cabin assigned");
    test:assertEquals(rows[0]["error_code"], 400);
}

@test:Config {}
function addonsCarryGuestAndReservation() {
    Chunk c = writtenChunk();
    json[] records = addonRecords(c);
    test:assertEquals(records.length(), 2);
    test:assertEquals(records[0], {
        "Addon_Code": "AIR-F", "Name": "R100|CL1|AIR-F", "Addon_Price": 50, "Addon_Category": "AIR",
        "Addon_Is_Special_Request": false, "Addon_Qty": "2", "Addon_Type": "SERVICE", "Addons_ID": "AD1",
        "Client_ID": "CL1", "Reservation_Addon": "Z-R100", "Guest_Name": "G-CL1"
    });
    Group[] groups = byReservation(ownedMerge(records, [{"Name": "R100|CL1|OLD"}]));
    test:assertEquals(writable(groups[0]).length(), 2);
    json[] answers = answersFor(groups[0], crmOk("Z-A1", "Z-A2"));
    map<json>[] rows = addonErrors(c, groups[0], answers);
    test:assertEquals(rows.length(), 1);
    test:assertEquals(rows[0]["failure_reason"], "No addons assigned");
    test:assertEquals(rows[0]["package_name"], "PKG1");
}

// ---------------------------------------------------------------- groups, voyages, invoices

@test:Config {}
function groupRequestAndErrors() {
    Chunk c = sampleChunk();
    json request = groupRequest(c);
    test:assertEquals(first(request), {"Agency_ID": "AG1", "Agent_ID": "GA1", "Email": "group@example.test",
        "Group_ID": "G1", "Source_System": "Seaware", "Name": "Group One"});
    test:assertEquals(f(request, "duplicate_check_fields"), ["Group_ID"]);
    c.groupAnswer = {"data": [{"status": "error", "errorCode": 400, "message": "Group-Agency : bad"}]};
    test:assertEquals(groupErrors(c)[0]["module_name"], "Group-Agency");
}

@test:Config {}
function voyageComesFromTheFirstGuest() {
    json rec = first(voyageRequest(f(sampleEdge("R100"), "node")));
    test:assertEquals(f(rec, "Name"), "PKG1");
    test:assertEquals(f(rec, "Arrival_Port_Key"), "YNB");
    test:assertEquals(f(rec, "Departure_Date_and_Time"), "2026-04-01T16:00:00");
    test:assertEquals(f(rec, "Destination_Name"), "Red Sea");
    test:assertEquals(f(rec, "Cruise_Duration_Number_of_Nights"), 4);
    test:assertEquals(f(rec, "Ship_ID"), "SHIP1");
    test:assertEquals(f(rec, "Package"), "4 nights");
    Chunk c = sampleChunk();
    c.voyageAnswers = [{"data": [{"status": "error", "errorCode": 400, "message": "voyages : Name-bad"}]}];
    test:assertEquals(voyageErrors(c).length(), 2);
}

@test:Config {}
function invoiceRequestLinksReservationAndContact() {
    json request = invoiceRequest(writtenChunk());
    json rec = first(request);
    test:assertEquals(f(rec, "Name"), "9001");
    test:assertEquals(f(rec, "Invoice_Number"), "9001");
    test:assertEquals(f(rec, "Contact"), {"id": "G-CL1"});
    test:assertEquals(f(rec, "Reservation_Name"), {"id": "Z-R100"});
    test:assertEquals(f(rec, "Coupon_key_discount"), ["CP1"]);
    test:assertEquals(f(rec, "Promotion_Code"), "PR1");
    test:assertEquals(f(rec, "Addons_Total"), 50);
    test:assertEquals(f(rec, "Shorex_Total"), 25);
    test:assertEquals(f(rec, "Balance_Due"), 200);
    test:assertEquals(f(rec, "Due_Type"), "DEPOSIT");
    test:assertEquals(f(rec, "Payment_Schedule"), [{"Paid": true, "Payment_Amount_Paid": "100", "Payment_Date": "2026-02-01", "Payment_Type": "DEPOSIT"}]);
    test:assertEquals(f(rec, "Payment_Received"), [{"Payment_Amount_Paid": "100", "Payment_Date": "2026-01-05", "Payment_Method": "CARD", "Price_to_Base_Currency_Rate": "1"}]);
    test:assertEquals(f(request, "duplicate_check_fields"), ["Name"]);
}

// ---------------------------------------------------------------- refusals and the error table

@test:Config {}
function crmRefusalsKeepTheOldShapes() {
    Answer named = {status: 400, failure: "HTTP 400", body: {"targetError": {"data": [
        {"message": "invalid data", "details": {"api_name": "Currency"}}, {"message": "plain"}]}}};
    test:assertEquals(refusedData(named, "reservation : ", 2, true), [
        {"status": "error", "errorCode": 400, "message": "reservation : Currency-invalid data"},
        {"status": "error", "errorCode": 400, "message": "HTTP 400"}
    ]);
    Answer single = {status: 400, failure: "HTTP 400", body: {"targetError": {"message": "too long"}}};
    test:assertEquals(refusedData(single, "Addons : ", 1, false), [{"status": "error", "errorCode": 400, "message": "Addons : too long"}]);
    Answer unreadable = {status: 500, unreadable: true, failure: "CONNECTIVITY"};
    test:assertEquals(refusedData(unreadable, "invoice : ", 2, true).length(), 2);
}

@test:Config {}
function errorRowsBecomeOneInsert() {
    Chunk c = sampleChunk();
    map<json>[] rows = [errorRow(c, "Cabin", "R100", (), "PKG1", "CL2", "it's missing", ())];
    json request = errorInsert("the_table", rows);
    test:assertEquals(f(request, "connectionKey"), "PG_Guest");
    test:assertEquals(f(request, "operation"), "insert");
    test:assertEquals(f(request, "query"), "INSERT INTO the_table (reservation_number, correlation_id, cabin_number, source_system, module_name, "
        + "package_name, client_id, batch_job_name, failure_reason, error_code) VALUES ('R100', 'run-1', NULL, 'Seaware', 'Cabin', "
        + "'PKG1', 'CL2', 'delta', 'it\"s missing', 500)");
    test:assertEquals(errorInsert("the_table", []), ());
    test:assertEquals(writeErrorRows((), "the_table", rows, "run-1"), "error table address or name not set");
}

// ---------------------------------------------------------------- queue

function sampleMessage() returns string {
    string notification = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><ns:ResStoreNotification xmlns:ns=\"urn:example\"><ns:ResHeader>"
        + "<ns:ResID>R200</ns:ResID><ns:ResStatus>BK</ns:ResStatus><ns:Version>4</ns:Version><ns:AgencyID>AG9</ns:AgencyID>"
        + "<ns:Currency>SAR</ns:Currency><ns:InitialDate>2026-01-01T09:00:00</ns:InitialDate><ns:LastUpdatedAt>2026-01-03T11:00:00</ns:LastUpdatedAt>"
        + "<ns:InvoiceTotals><ns:InvoiceTotal>900</ns:InvoiceTotal><ns:InvoicePaid>300</ns:InvoicePaid><ns:NetDue>600</ns:NetDue>"
        + "<ns:IsPaidInFull>N</ns:IsPaidInFull><ns:CurrentDue><ns:AmountDue>600</ns:AmountDue><ns:DueDate>2026-02-01T00:00:00</ns:DueDate>"
        + "<ns:DueType>FINAL</ns:DueType></ns:CurrentDue></ns:InvoiceTotals><ns:LastInvoice><ns:InvoiceID>7001</ns:InvoiceID></ns:LastInvoice>"
        + "</ns:ResHeader></ns:ResStoreNotification>";
    return {"subscription": {"message": notification}}.toJsonString();
}

@test:Config {}
function queueMessageBecomesReservationAndInvoice() returns error? {
    xml:Element header = check reservationHeader(sampleMessage());
    json reservation = queueReservationRequest(header);
    test:assertEquals(f(reservation, "data"), [{
        "Agency_ID": "AG9", "Balance_Due": "600", "Currency": "SAR", "Due_Date": "2026-02-01", "Invoice_Total": "900",
        "Account_Name": "Reservation|R200", "Account_Number": "R200", "Reservation_Status": "BK", "Reservation_Version": "4",
        "Reservation_Created_On": "2026-01-01T09:00:00", "Reservation_Last_Updated": "2026-01-03T11:00:00", "Agency_key": "AG9"
    }]);
    test:assertEquals(f(reservation, "duplicate_check_fields"), ["Account_Name"]);
    json invoice = queueInvoiceRequest(header, "Z-R200");
    test:assertEquals(f(invoice, "data"), [{
        "Name": "7001", "Currency": "SAR", "Invoice_Number": "7001", "Reservation_Name": {"id": "Z-R200"},
        "Total_Invoice": "900", "Due_Date": "2026-02-01", "Balance_Due": "600", "Due_Type": "FINAL",
        "Payment_Schedule": [{"Paid": false, "Payment_Amount_Paid": "600"}],
        "Payment_Received": [{"Payment_Amount_Paid": "300"}]
    }]);
}

@test:Config {}
function queueMessageOfAnotherShapeIsRefused() {
    test:assertTrue(reservationHeader("not json") is error);
    test:assertTrue(reservationHeader("{\"subscription\":{}}") is error);
    test:assertTrue(reservationHeader("{\"subscription\":{\"message\":\"<a><b/></a>\"}}") is error);
}

// Runs only when a local stand-in is given (never against a real system): the queue handler end to end.
@test:Config {}
function queueMessageAgainstTheStandIn() returns error? {
    string base = os:getEnv("SYNC_DOUBLE_URL");
    if base == "" {
        return;
    }
    Backend zoho = check new ("CRM system service", {url: base + "/zoho"}, {retryWaitSeconds: 0});
    QueueWork work = new (zoho, {});
    check work.process(sampleMessage());
}
