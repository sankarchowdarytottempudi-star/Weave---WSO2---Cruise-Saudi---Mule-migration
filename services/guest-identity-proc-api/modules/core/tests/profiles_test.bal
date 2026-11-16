import ballerina/test;

@test:Config {}
function bookingInfoFromTheCrm() {
    test:assertEquals(bookingInfoCriteriaOf("L1", "G1"), "((Aroya_Loyalty_ID:equals:L1)and(Global_Guest_ID:equals:G1))");
    map<json> info = bookingInfoOf({"data": [{"First_Name": "ANN", "Phone": "966500001234", "Residency": "Saudi Arabia"}]});
    test:assertEquals(info["firstName"], "ANN");
    test:assertEquals(info["internationalCode"], "+966");
    test:assertEquals(info["phone"], "500001234");
    test:assertEquals(info["countryOfResidence"], "Saudi Arabia");
    test:assertEquals(bookingInfoOf({"data": [{"Phone": "12345"}]})["phone"], "12345");
    test:assertEquals(bookingInfoOf({"data": [{"Phone": "12345"}]})["internationalCode"], ());
    test:assertEquals(bookingInfoOf(())["firstName"], ());
}

@test:Config {}
function newestProfilePerPerson() {
    json[] records = [
        {"id": "1", "Email": "a@b.co", "First_Name": "ANN", "Last_Name": "LEE", "Modified_Time": "2026-01-01"},
        {"id": "2", "Email": "A@B.CO", "First_Name": "Ann", "Last_Name": "Lee", "Modified_Time": "2026-05-01"},
        {"id": "3", "Email": "a@b.co", "First_Name": "BOB", "Last_Name": "LEE", "Modified_Time": "2026-09-01"}
    ];
    json[] latest = latestProfilesOf(records);
    test:assertEquals(latest.length(), 2);
    test:assertEquals(fieldOf(latest[0], "id"), "3");
    test:assertEquals(fieldOf(latest[1], "id"), "2");
}

@test:Config {}
function pages() {
    json[] records = [1, 2, 3, 4, 5];
    test:assertEquals(pageOf(records, 1, 2), <json[]>[1, 2]);
    test:assertEquals(pageOf(records, 3, 2), <json[]>[5]);
    test:assertEquals(pageOf(records, 4, 2), <json[]>[]);
    test:assertEquals(fieldOf(profilesAnswerOf([], 3, 2, 5), "profile", "pagination"),
            <json>{"page": 3, "perPage": 2, "totalRecords": 5, "totalPages": 3});
}

@test:Config {}
function profileOfAContact() {
    map<json> profile = profileOf({"Client_ID": "77", "Email": "a@b.co", "Gender": "M", "Mobile": "+966500001234",
                "City": "Jeddah", "Aroya_Loyalty_ID": "L1"}, "PIC");
    test:assertEquals(profile["clientId"], "77");
    test:assertEquals(profile["profileImage"], "PIC");
    test:assertEquals(fieldOf(profile, "loyalty", "loyaltyId"), "L1");
    test:assertEquals(fieldOf(profile, "personalInformation", "gender"), "Male");
    test:assertEquals(fieldOf(profile, "personalInformation", "phoneNumber"), "+966500001234");
    test:assertEquals(fieldOf(profile, "personalInformation", "city"), "Jeddah");
    test:assertEquals(fieldOf(profileOf({"Mobile": "9665"}, ()), "personalInformation", "phoneNumber"), "+9665");
    test:assertEquals(fieldOf(profileOf({}, ()), "personalInformation", "phoneNumber"), ());
}

function reservation(int id, string contact, string fromDate, string toDate, string... clients) returns json {
    json[] guests = [];
    foreach int i in 0 ..< clients.length() {
        guests.push({
            "seqN": i + 1,
            "client": {"key": clients[i], "fullName": "Guest " + clients[i], "gender": "F"},
            "voyages": [{"sail": {"from": {"dateTime": fromDate + "T16:00:00"}, "to": {"dateTime": toDate + "T08:00:00"}}}]
        });
    }
    return {"node": {"id": id, "key": "R" + id.toString(), "contact": {"key": contact}, "guests": guests}};
}

@test:Config {}
function tripsAreSortedIntoNowLaterAndBefore() {
    json answer = {"data": {"reservations": {"edges": [
                    reservation(1, "C1", "2026-11-10", "2026-11-20", "C1", "C2"),
                    reservation(2, "C9", "2026-12-01", "2026-12-08", "C9", "C1", "C2"),
                    reservation(3, "C1", "2026-10-01", "2026-10-05", "C1", "C2", "C3"),
                    reservation(4, "C7", "2026-11-10", "2026-11-20", "C7", "C8")
                ]}}};
    map<json> trips = tripsAnswerOf(answer, "C1", "2026-11-15");
    test:assertEquals(listOf(fieldOf(trips, "trips", "Current Trips")).length(), 1);
    test:assertEquals(fieldOf(listOf(fieldOf(trips, "trips", "Current Trips"))[0], "bookingId"), 1);
    test:assertEquals(fieldOf(listOf(fieldOf(trips, "trips", "Future Trips"))[0], "bookingId"), 2);
    test:assertEquals(fieldOf(listOf(fieldOf(trips, "trips", "Old Trips"))[0], "bookingId"), 3);
    // Companions come from the reservations where C1 is the primary guest, each one once.
    json[] companions = listOf(trips["familyAndFriends"]);
    test:assertEquals(companions.length(), 2);
    test:assertEquals(fieldOf(companions[0], "clientId"), "C2");
    test:assertEquals(fieldOf(companions[0], "gender"), "Female");
    test:assertEquals(fieldOf(companions[1], "clientId"), "C3");
    test:assertEquals(listOf(fieldOf(tripsAnswerOf((), "C1", "2026-11-15"), "trips", "Current Trips")).length(), 0);
}

@test:Config {}
function nameParts() {
    test:assertEquals(namePartsOf("  John  Ronald Smith "), ["John", "Ronald Smith"]);
    test:assertEquals(namePartsOf("Cher"), ["Cher", ""]);
    test:assertEquals(namePartsOf(()), ["", ""]);
}

final map<json> & readonly edit = {
    "profileImage": "",
    "personalInformation": {
        "fullName": "John O'Neil",
        "gender": "Male",
        "country": "Saudi Arabia",
        "city": "Jeddah",
        "username": "john@example.com",
        "phoneNumber": "+966500001234",
        "language": "Arabic"
    }
};

@test:Config {}
function seawareClientEdit() {
    string query = textOf(clientUpdateQueryOf("77", edit)["query"]);
    test:assertTrue(query.includes("id: \"Client|77\""));
    test:assertTrue(query.includes("firstName: \"John\", lastName: \"O'Neil\", gender: M, mobileIntlCode: 966, "));
    test:assertTrue(query.includes("mobilePhoneNumber: \"500001234\""));
    test:assertTrue(query.includes("citizenship: { key: [\"SA\"] }"));
    test:assertTrue(query.includes("language: { key: [\"AR\"] }"));
    test:assertTrue(query.includes("addresses: { city: \"Jeddah\", type: { key: \"PRIMARY\" } }"));
    test:assertTrue(reservationsQueryOf("7\"7")["query"].toString().includes("key: \"7\\\"7\""));
}

@test:Config {}
function crmContactEdit() {
    map<json> contact = editContactOf("77", edit);
    test:assertEquals(contact["Client_ID"], "77");
    test:assertEquals(contact["Email"], "john@example.com");
    test:assertEquals(contact["First_Name"], "JOHN");
    test:assertEquals(contact["Last_Name"], "O'NEIL");
    test:assertEquals(contact["Mobile"], "+966500001234");
    test:assertEquals(contact["Preferred_Language"], "Arabic");
    test:assertFalse(contact.hasKey("Date_of_Birth"));
}

@test:Config {}
function guestStoreEdit() {
    string query = textOf(editGuestCoreOf("7'7", edit, "2026-11-15T10:00:00Z")["query"]);
    test:assertTrue(query.includes("first_name = 'JOHN', last_name = 'O''NEIL', email = 'john@example.com'"));
    test:assertTrue(query.includes("WHERE seaware_client_id = '7''7' RETURNING id"));
    test:assertTrue(query.includes("updated_by = '2026-11-15T10:00:00Z'"));
}

@test:Config {}
function editAnswers() {
    json seaware = {"data": {"clientUpdate": {"result": {"key": 77}}}};
    json crm = {"data": [{"status": "success", "details": {"id": "Z9"}}]};
    [int, map<json>] [status, body] = editAnswerOf(edit, seaware, crm, ());
    test:assertEquals(status, 200);
    test:assertEquals(body["status"], "Success");
    test:assertEquals(body["ClientId"], "77");
    test:assertEquals(body["zohoId"], "Z9");
    test:assertEquals(body["profileImageUpdated"], false);
    test:assertEquals(body["updatedFieldsCount"], 8);
    test:assertEquals(body["errorMessage"], "");

    [int, map<json>] [noClient, noClientBody] = editAnswerOf(edit, {"errors": [{"message": "x"}]}, crm, ());
    test:assertEquals(noClient, 400);
    test:assertEquals(noClientBody["ClientId"], ());

    [int, map<json>] [crmFailed, crmFailedBody] = editAnswerOf(edit, seaware,
            {"data": [{"status": "error", "message": "invalid data"}]}, ());
    test:assertEquals(crmFailed, 400);
    test:assertEquals(crmFailedBody["errorMessage"], "invalid data");

    map<json> withImage = copyOf(edit);
    withImage["profileImage"] = "AAAA";
    [int, map<json>] [imageFailed, imageFailedBody] = editAnswerOf(withImage, seaware, crm,
            {"status": "error", "message": "too large"});
    test:assertEquals(imageFailed, 400);
    test:assertEquals(imageFailedBody["profileImageUpdated"], false);
    test:assertEquals(imageFailedBody["errorMessage"], "too large");
}

@test:Config {}
function deviceLinks() {
    map<json> body = {"profileId": "P1", "client_deviceId": "D1", "client_channel": "mobile", "seaware_client_id": "77",
        "first_name": "Ann"};
    test:assertEquals(bookingLoginShoreOf(body)["params"], <json>{"profileId": "P1", "deviceId": "D1", "deviceType": "mobile"});
    test:assertEquals(fieldOf(bookingLoginShipGuestOf(body), "params", "seawareClientId"), "77");
    test:assertEquals(fieldOf(bookingLoginShipGuestOf(body), "params", "lastName"), ());
    test:assertEquals(bookingLoginShipDeviceOf(body)["params"],
            <json>{"seawareClientId": "77", "deviceId": "D1", "deviceType": "mobile"});
    test:assertEquals(tripsDeviceLinkOf("D1", "mobile", "77")["params"],
            <json>{"deviceId": "D1", "deviceType": "mobile", "clientId": "77"});
}

// Mule mapCabins: one entry per cabin (first-seen order), its guests with clientId cast to String,
// fullName and primarySailor (seqN == 1); the per-row helper fields are not part of the answer.
@test:Config {}
function cabinsLikeTheOldMapCabins() {
    json[] guests = [
        {"seqN": 1, "client": {"key": 1001, "fullName": "Ann One"},
            "voyages": [{"cabinChain": [{"cabin": {"number": "8012", "category": {"code": "S1", "comments": "Suite"}, "deck": {"number": 8}}}]}]},
        {"seqN": 2, "client": {"key": "1002", "fullName": "Bob Two"},
            "voyages": [{"cabinChain": [{"cabin": {"number": "8012", "category": {"code": "S1", "comments": "Suite"}, "deck": {"number": 8}}},
                                        {"cabin": {"number": "8014", "category": {"code": "B2", "comments": "Balcony"}, "deck": {"number": 8}}}]}]},
        {"seqN": 3, "client": {"fullName": "No Key"}, "voyages": [{"cabinChain": [{"cabin": ()}]}]}
    ];
    json[] cabins = cabinsOf(guests);
    test:assertEquals(cabins.length(), 2);
    test:assertEquals(cabins[0], {"number": "8012", "category": "S1", "cabinType": "Suite", "deck": 8,
        "guests": [{"clientId": "1001", "fullName": "Ann One", "primarySailor": true},
                   {"clientId": "1002", "fullName": "Bob Two", "primarySailor": false}]});
    test:assertEquals(cabins[1], {"number": "8014", "category": "B2", "cabinType": "Balcony", "deck": 8,
        "guests": [{"clientId": "1002", "fullName": "Bob Two", "primarySailor": false}]});
    // a guest without a client key: clientId stays null, as `null as String` does in DataWeave
    json[] alone = cabinsOf([{"seqN": 1, "client": {"fullName": "No Key"},
        "voyages": [{"cabinChain": [{"cabin": {"number": "9001"}}]}]}]);
    test:assertEquals(alone[0].guests, [{"clientId": (), "fullName": "No Key", "primarySailor": true}]);
}
