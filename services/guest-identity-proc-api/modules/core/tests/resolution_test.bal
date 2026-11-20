import ballerina/test;

final string[] codes = ["INT-ASSC", "MOBAPP", "IN HOUSE"];
final string[] agencies = ["AROYA CRUISES MAIN OFFICE", "RIYADH SEASON"];

@test:Config {}
function resolutionScopeNeedsSourceCodeAndAgency() {
    test:assertTrue(inResolutionScope({"sourceCode": " mobapp", "agencyName": "Riyadh Season "}, "sourceCode",
                                      "agencyName", codes, agencies));
    test:assertFalse(inResolutionScope({"sourceCode": "MOBAPP", "agencyName": "OTHER AGENCY"}, "sourceCode",
                                       "agencyName", codes, agencies));
    test:assertFalse(inResolutionScope({"sourceCode": "TA", "agencyName": "RIYADH SEASON"}, "sourceCode",
                                       "agencyName", codes, agencies));
    test:assertFalse(inResolutionScope({"firstName": "X"}, "sourceCode", "agencyName", codes, agencies));
}

@test:Config {}
function pendingContactHasNoIds() {
    map<json> c = pendingContactOf({"Client_ID": "C1", "Global_Guest_ID": "", "Aroya_Loyalty_ID": "", "First_Name": "A"},
                                   "SEAWARE", "MOBAPP", "");
    test:assertEquals(c, {
                             "Client_ID": "C1",
                             "First_Name": "A",
                             "Identity_Status": "PENDING_IDENTITY",
                             "Direct_Scope": true,
                             "Source_System": "SEAWARE"
                         });
    test:assertEquals(pendingContactOf({}, "SEAWARE", "MOBAPP", "Lead_Source")["Lead_Source"], "MOBAPP");
}

@test:Config {}
function evaluationEventFromTheUpsert() {
    json answer = {
        "data": [
            {
                "code": "SUCCESS",
                "status": "success",
                "details": {"id": "Z1", "Modified_Time": "2026-11-16T10:20:30+03:00"}
            }
        ]
    };
    map<json> contact = {
        "Client_ID": "C1",
        "First_Name": "ANN",
        "Last_Name": "RAY",
        "Date_of_Birth": "1991-05-06",
        "Mobile": "9005551001",
        "Email": "a@example.test"
    };
    map<json> e = evaluationEventOf({"countryOfResidenceKey": "SA", "nationalityKey": "SA"}, contact, answer, "SEAWARE",
                                    "MOBAPP", "AROYA CRUISES MAIN OFFICE", "CORR-1", "EV-1") ?: {};
    test:assertEquals(e["idempotencyKey"], "SEAWARE:C1:2026-11-16T10:20:30+03:00");
    test:assertEquals(e["crmGuestRecordId"], "Z1");
    test:assertEquals(e["eventType"], "GUEST_IDENTITY_EVALUATION_REQUESTED");
    test:assertEquals(e["schemaVersion"], "1.0");
    test:assertEquals(e["phone"], "9005551001");
    test:assertEquals(e["countryCode"], "SA");
    test:assertEquals(e["agencyName"], "AROYA CRUISES MAIN OFFICE");
    test:assertFalse(e.hasKey("currentGlobalId"));
    test:assertTrue(evaluationEventOf({}, contact, {"data": []}, "SEAWARE", "", "", "C", "E") is ());
}
