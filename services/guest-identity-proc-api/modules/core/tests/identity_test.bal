import ballerina/test;

final map<json> & readonly ann = {
    "firstName": "Ann",
    "lastName": "Lee",
    "intlCode": "966",
    "phone": "500001234",
    "email": "ann@example.com",
    "dateOfBirth": "1990-01-02",
    "gender": "f",
    "nationalityKey": "SA",
    "nationalityName": "saudi arabia",
    "countryOfResidenceKey": "SA",
    "countryOfResidenceName": "saudi arabia"
};

@test:Config {}
function channelsThatWriteToTheCrm() {
    test:assertTrue(channelAllowed(["mobile", "web"], "web"));
    test:assertFalse(channelAllowed(["mobile", "web"], "kiosk"));
    test:assertFalse(channelAllowed(["mobile", "web"], ()));
}

@test:Config {}
function genderNames() {
    test:assertEquals(genderName("m"), "Male");
    test:assertEquals(genderName("FEMALE"), "Female");
    test:assertEquals(genderName("x"), "Others");
}

@test:Config {}
function crmSearchNeedsEveryField() {
    test:assertTrue(completeMatch(ann));
    map<json> noBirthday = copyOf(ann);
    noBirthday["dateOfBirth"] = " ";
    test:assertFalse(completeMatch(noBirthday));
    test:assertEquals(searchCriteriaOf(ann), "((First_Name:equals:ANN)and(Last_Name:equals:LEE)and(Mobile:equals:966500001234)"
            + "and(Email:equals:ANN@EXAMPLE.COM)and(Date_of_Birth:equals:1990-01-02))");
}

@test:Config {}
function newestContactWithIdsIsSelected() {
    json[] records = [
        {"id": "1", "Global_Guest_ID": "G1", "Aroya_Loyalty_ID": "L1", "Modified_Time": "2026-01-01T00:00:00"},
        {"id": "2", "Global_Guest_ID": "G2", "Aroya_Loyalty_ID": "L2", "Modified_Time": "2026-03-01T00:00:00"},
        {"id": "3", "Global_Guest_ID": "old-style-id", "Aroya_Loyalty_ID": "L3", "Modified_Time": "2026-09-01T00:00:00"},
        {"id": "4", "Global_Guest_ID": "G4", "Modified_Time": "2026-10-01T00:00:00"}
    ];
    map<json>? selected = selectedRecordOf(records);
    test:assertEquals(selected is () ? () : selected["id"], "2");
    test:assertEquals(selectedRecordOf([]), ());
}

@test:Config {}
function existingContactsGetTheIds() {
    json[] updates = existingUpdatesOf([{"id": "9", "Client_ID": "77", "Account_Name": {"name": "Acme"}}], ann, "G1", "L1");
    test:assertEquals(updates.length(), 1);
    test:assertEquals(fieldOf(updates[0], "id"), "9");
    test:assertEquals(fieldOf(updates[0], "Client_ID"), "77");
    test:assertEquals(fieldOf(updates[0], "First_Name"), "ANN");
    test:assertEquals(fieldOf(updates[0], "Nationality"), "Saudi Arabia");
    test:assertEquals(fieldOf(updates[0], "Global_Guest_ID"), "G1");
    test:assertEquals(fieldOf(updates[0], "Aroya_Loyalty_ID"), "L1");
    test:assertEquals(fieldOf(updates[0], "Account_Name"), "Acme");
}

@test:Config {}
function clientSearchRequest() {
    test:assertTrue(hasClientSearch(ann));
    test:assertFalse(hasClientSearch({"email": "not an address"}));
    string query = textOf(clientsQueryOf(ann)["query"]);
    test:assertTrue(query.includes("firstName: \"Ann\", lastName: \"Lee\", eMail: \"ann@example.com\", phoneNumber: \"500001234\""));
}

@test:Config {}
function givenClientThatSeawareDoesNotFindIsKept() {
    map<json> guest = copyOf(ann);
    guest["clientId"] = "555";
    ClientPlan plan = clientPlanOf(guest, {"data": {"clients": {"edges": []}}}, "L1|G1");
    test:assertEquals(plan.kind, "none");
    test:assertEquals(plan.updateClient, "555");
}

@test:Config {}
function givenClientIsUpdated() {
    map<json> guest = copyOf(ann);
    guest["clientId"] = "555";
    ClientPlan plan = clientPlanOf(guest, {"data": {"clients": {"edges": [{"node": {"key": "1"}}]}}}, "L1|G1");
    test:assertEquals(plan.kind, "update");
    test:assertTrue(plan.query.includes("id: \"Client|555\""));
    test:assertTrue(plan.query.includes("comments: \"L1|G1\""));
}

@test:Config {}
function matchingClientIsUpdated() {
    json clients = {"data": {"clients": {"edges": [
                    {"node": {"key": "1", "citizenship": {"key": "AE"}, "countryOfResidence": {"key": "AE"}}},
                    {"node": {"key": "2", "citizenship": {"key": "SA"}, "countryOfResidence": {"key": "SA"},
                            "countryOfBirth": {"key": "EG"}}}
                ]}}};
    ClientPlan plan = clientPlanOf(ann, clients, "L1|G1");
    test:assertEquals(plan.kind, "update");
    test:assertTrue(plan.query.startsWith("mutation ClientUpdate"));
    test:assertTrue(plan.query.includes("id: \"Client|2\""));
    test:assertTrue(plan.query.includes("gender: f, "));
    test:assertTrue(plan.query.includes("countryOfBirth: { key: [\"EG\"] }"));
}

@test:Config {}
function otherClientMeansANewOne() {
    json clients = {"data": {"clients": {"edges": [
                    {"node": {"key": "1", "citizenship": {"key": "AE"}, "countryOfResidence": {"key": "AE"}}}
                ]}}};
    ClientPlan plan = clientPlanOf(ann, clients, "|");
    test:assertEquals(plan.kind, "create");
    test:assertTrue(plan.query.startsWith("mutation ClientCreate"));
    test:assertTrue(plan.query.includes("comments: \"|\""));
    test:assertTrue(plan.query.includes("web: { allowAccess: true }"));
    test:assertEquals(clientPlanOf(ann, (), "|").kind, "create");
}

@test:Config {}
function unquotedValuesAreCleaned() {
    map<json> guest = copyOf(ann);
    guest["gender"] = "F } ) { logout";
    ClientPlan plan = clientPlanOf(guest, (), "|");
    test:assertTrue(plan.query.includes("gender: Flogout, "));
}

@test:Config {}
function clientIdsFromSeaware() {
    test:assertEquals(clientKeysOf({"data": {"clientUpdate": {"result": {"key": 12}}}}), ["12", ""]);
    test:assertEquals(clientKeysOf({"data": {"clientCreate": {"result": {"key": "34"}}}}), ["", "34"]);
    test:assertEquals(clientIdOf("", "34"), "34");
    test:assertEquals(clientIdOf("12", "34"), "12");
    test:assertEquals(clientOnlyAnswerOf("12"), {"status": "Success", "clientId": "12"});
    test:assertEquals(clientOnlyAnswerOf(""), {"status": "Error", "clientId": ""});
}

@test:Config {}
function crmContact() {
    map<json>|error contact = crmRecordOf(ann, "77", "G1", "L1");
    if contact is error {
        test:assertFail(contact.message());
    }
    test:assertEquals(contact["Client_ID"], "77");
    test:assertEquals(contact["First_Name"], "ANN");
    test:assertEquals(contact["Last_Name"], "LEE");
    test:assertEquals(contact["Gender"], "Female");
    test:assertEquals(contact["Mobile"], "966500001234");
    test:assertEquals(contact["Residency"], "Saudi Arabia");
    test:assertEquals(contact["Global_Guest_ID"], "G1");
    test:assertEquals(contact["Aroya_Loyalty_ID"], "L1");
    test:assertFalse(contact.hasKey("Middle_Name"));
    test:assertEquals(crmUpsertBodyOf(contact)["duplicate_check_fields"], <json>["Client_ID"]);
}

@test:Config {}
function crmContactNeedsAClient() {
    map<json>|error contact = crmRecordOf(ann, "", "G1", "L1");
    test:assertTrue(contact is error);
    if contact is error {
        test:assertEquals(contact.message(), "Client Id is empty");
    }
}

@test:Config {}
function crmAnswers() {
    json ok = {"data": [{"status": "success", "details": {"id": "Z9"}}]};
    json failed = {"data": [{"status": "error", "message": "invalid data", "details": {"api_name": "Email"}}]};
    test:assertFalse(isCrmError(ok));
    test:assertTrue(isCrmError(failed));
    test:assertTrue(isCrmError({"status": "error", "message": "down"}));
    test:assertEquals(crmContactIdOf(ok), "Z9");
    test:assertEquals(crmContactIdOf(()), "");

    map<json> contact = {"Global_Guest_ID": "G1", "Aroya_Loyalty_ID": "L1"};
    test:assertEquals(identityAnswerOf(ok, (), contact, "77"), {
        "status": "Success",
        "clientId": "77",
        "globalGuestId": "G1",
        "loyaltyId": "L1",
        "zohoId": "Z9",
        "errorMessage": ""
    });
    map<json> bad = identityAnswerOf(failed, (), contact, "77");
    test:assertEquals(bad["status"], "Error");
    test:assertEquals(bad["errorMessage"], "Email - invalid data");
    test:assertEquals(bad["zohoId"], ());
    map<json> image = identityAnswerOf(ok, {"status": "error", "message": "too large"}, contact, "77");
    test:assertEquals(image["status"], "Error");
    test:assertEquals(image["errorMessage"], "too large");
}

@test:Config {}
function pictures() {
    test:assertEquals(plainBase64("data:image/png;base64,AAAA"), "AAAA");
    test:assertEquals(plainBase64(" AAAA "), "AAAA");
    test:assertEquals(photoPathOf("/crm/v8/Contacts/{contactId}/photo", "Z9"), "/crm/v8/Contacts/Z9/photo");
}

@test:Config {}
function guestStoreRequests() {
    map<json> contact = {"Global_Guest_ID": "G1", "Aroya_Loyalty_ID": "L1", "Client_ID": "77", "First_Name": "ANN",
        "Last_Name": "O'NEIL", "Email": "ann@example.com"};
    map<json> request = guestCoreUpsertOf(contact, {"data": [{"details": {"id": "Z9"}}]});
    string query = textOf(request["query"]);
    test:assertEquals(request["operation"], "select");
    test:assertTrue(query.includes("(global_guest_id, loyalty_id, zoho_contact_id, seaware_client_id, first_name, last_name, email)"));
    test:assertTrue(query.includes("('G1', 'L1', 'Z9', '77', 'ANN', 'O''NEIL', 'ann@example.com')"));
    string link = textOf(deviceLinkOf("id-1", "dev'1", "mobile")["query"]);
    test:assertTrue(link.includes("VALUES ('id-1', 'dev''1', 'mobile')"));
}
