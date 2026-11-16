import ballerina/lang.array;
import ballerina/test;

@test:Config {}
function directScopeNeedsBothConditions() {
    DirectScope s = {};
    test:assertTrue(inDirectScope("mobapp ", " Aroya Cruises Main Office", s));
    test:assertTrue(inDirectScope("IN HOUSE", "RIYADH SEASON", s));
    test:assertFalse(inDirectScope("MOBAPP", "SOME TRAVEL AGENCY", s));
    test:assertFalse(inDirectScope("TA-WEB", "AROYA CRUISES MAIN OFFICE", s));
    test:assertFalse(inDirectScope("", "AROYA CRUISES MAIN OFFICE", s));
    test:assertFalse(inDirectScope("MOBAPP", "", s));
}

@test:Config {}
function snapshotOfACrmGuest() {
    map<json> rec = {
        "id": "G1",
        "Modified_Time": "2026-11-16T10:20:30+03:00",
        "First_Name": "A",
        "Last_Name": "B",
        "Date_of_Birth": "1985-05-10",
        "Mobile": "+966 55",
        "Email": "a@b.invalid",
        "Country": "SA",
        "Nationality": "SA",
        "Lead_Source": "MOBAPP",
        "Account_Name": {"name": "AROYA CRUISES MAIN OFFICE", "id": "1"},
        "Source_System": "SEAWARE",
        "Client_ID": "123",
        "Global_Guest_ID": "01J",
        "Aroya_Loyalty_ID": "12",
        "Guest_Identity": {"id": "I1"},
        "Phone": ""
    };
    map<json> e = snapshotEventOf(rec, REEVALUATION, CRM_DIRECT, "C1");
    test:assertEquals(e["sourceSystem"], "SEAWARE");
    test:assertEquals(e["sourceRecordId"], "123");
    test:assertEquals(e["idempotencyKey"], "SEAWARE:123:2026-11-16T10:20:30+03:00");
    test:assertEquals(e["agencyName"], "AROYA CRUISES MAIN OFFICE");
    test:assertEquals(e["currentIdentityId"], "I1");
    test:assertEquals(e["phone"], "+966 55");
    test:assertEquals(e["eventType"], REEVALUATION);
    map<json> direct = snapshotEventOf({"id": "G2", "Modified_Time": "t", "Account_Name": "X"}, EVALUATION, CRM_DIRECT, "C");
    test:assertEquals(direct["sourceSystem"], CRM_DIRECT);
    test:assertEquals(direct["sourceRecordId"], "G2");
    test:assertEquals(direct["agencyName"], "X");
    test:assertFalse(direct.hasKey("firstName"));
    test:assertTrue(snapshotFieldsOf().indexOf("Modified_Time") is int);
}

@test:Config {}
function decisionToCrmRecords() {
    map<json> d = {
        decisionId: "IDDEC-1",
        decisionType: "NEW",
        identityStatus: "NEW_IDENTITY_CREATED",
        globalId: "01J",
        loyaltyId: "12",
        ruleVersion: "1.0",
        reasonCodes: ["A", "B"],
        provisional: false,
        reviewCaseId: "RC-1",
        reviewPriority: "HIGH"
    };
    map<json> idr = identityRecordOf(d) ?: {};
    test:assertEquals(idr["Global_ID"], "01J");
    test:assertEquals(idr["Identity_Lifecycle"], "ACTIVE");
    test:assertEquals(idr["Created_By_Process"], "NEW");
    map<json> prov = identityRecordOf({globalId: "g", loyaltyId: "l", provisional: true}) ?: {};
    test:assertEquals(prov["Identity_Lifecycle"], "PROVISIONAL");
    test:assertEquals(prov["Created_By_Process"], "REVIEW");
    test:assertEquals((identityRecordOf({globalId: "g", loyaltyId: "l", decisionType: "CERTAIN_PHONE"}) ?: {})["Created_By_Process"], "CERTAIN");
    test:assertTrue(identityRecordOf({globalId: "g", loyaltyId: "l", crmIdentityRecordId: "I"}) is ());
    test:assertTrue(identityRecordOf({}) is ());
    map<json> p = contactPatchOf(d, "I9", "C");
    test:assertEquals(p["Identity_Reason_Codes"], "A, B");
    test:assertEquals(p["Guest_Identity"], {"id": "I9"});
    test:assertEquals(p["Identity_Review_Case_ID"], "RC-1");
    test:assertEquals(p["Global_Guest_ID"], "01J");
    test:assertFalse(p.hasKey(""));
    map<json> p2 = contactPatchOf({decisionId: "x"}, "", "C", {correlationId: "Corr"});
    test:assertEquals(p2["Corr"], "C");
    test:assertFalse(p2.hasKey("Guest_Identity"));
    map<json> rc = reviewCaseRecordOf({reviewCaseId: "RC-1", decisionType: "FOUR_FIELD", reviewPriority: "HIGH"}, "G1", "I1") ?: {};
    test:assertEquals(rc["Case_Kind"], "FOUR_FIELD_REVIEW");
    test:assertEquals(rc["Priority"], "HIGH");
    test:assertEquals(rc["Provisional_Identity"], {"id": "I1"});
    foreach [string, string] [t, k] in [
        ["MULTIPLE_IDENTITY", "MULTIPLE_IDENTITY_CONFLICT"],
        ["PAIR_REPAIR", "PAIR_REPAIR"],
        ["GUARDRAIL", "GUARDRAIL"]
    ] {
        test:assertEquals((reviewCaseRecordOf({reviewCaseId: "R", decisionType: t}, "G", "") ?: {})["Case_Kind"], k);
    }
    test:assertFalse((reviewCaseRecordOf({reviewCaseId: "R", decisionType: "NEW"}, "G", "") ?: {}).hasKey("Case_Kind"));
    test:assertTrue(reviewCaseRecordOf({}, "G", "") is ());
}

@test:Config {}
function reviewWritesInControlledOrder() returns error? {
    CrmWrite[] w = check reviewWritesOf({
                                            identityStatus: "CONFIRMED_SAME_PERSON",
                                            reviewCaseId: "RC-1",
                                            reviewAction: "CONFIRM_SAME_PERSON",
                                            guestIdentityId: "I200",
                                            aliasIdentityId: "I100"
                                        }, "G1", "RC-1", "U1", "RD-1");
    test:assertEquals(w.length(), 3);
    test:assertEquals(w[0].module, "Guest_Identities");
    test:assertEquals(w[0].id, "I100");
    test:assertEquals(w[0].fields["Identity_Lifecycle"], "ALIAS");
    test:assertEquals(w[0].fields["Surviving_Identity"], {"id": "I200"});
    test:assertEquals(w[1].module, "Contacts");
    test:assertEquals(w[1].fields["Guest_Identity"], {"id": "I200"});
    test:assertEquals(w[1].fields["Identity_Decision_Type"], "MANUAL");
    test:assertEquals(w[2].module, "Identity_Review_Cases");
    test:assertEquals(w[2].upsertKey, "Case_ID");
    test:assertEquals(w[2].fields["Case_Status"], "REVIEW_COMMITTED");

    CrmWrite[] h = check reviewWritesOf({
                                            identityStatus: "HOUSEHOLD_RELATIONSHIP",
                                            reviewAction: "CONFIRM_HOUSEHOLD",
                                            guestIdentityId: "I1",
                                            householdWith: ["I2", "I3", "I1"],
                                            householdId: "HH-1",
                                            globalId: "g",
                                            loyaltyId: "l"
                                        },
                                        "G1", "RC-2", "U1", "RD-2");
    test:assertEquals(h.length(), 5);
    test:assertEquals(h[3].fields["Household_ID"], "HH-1");
    test:assertEquals(h[3].fields["Global_Guest_ID"], "g");

    CrmWrite[] defer = check reviewWritesOf({
                                                identityStatus: "NEW_IDENTITY_PENDING_REVIEW",
                                                reviewAction: "DEFER",
                                                followUpDate: "2026-11-20T00:00:00Z"
                                            }, "G1", "RC-3", "U1", "RD-3");
    test:assertEquals(defer.length(), 2);
    test:assertEquals(defer[1].fields["Case_Status"], "REVIEW_OPEN");
    test:assertEquals(defer[1].fields["Follow_Up_Date"], "2026-11-20");

    test:assertTrue(reviewWritesOf({unknown: 1}, "G1", "RC", "U", "RD") is error);
    test:assertTrue(reviewWritesOf("x", "G1", "RC", "U", "RD") is error);
    test:assertTrue(reviewWritesOf({}, "", "RC", "U", "RD") is error);
}

@test:Config {}
function freshnessComparison() {
    json toCheck = [
        {crmGuestRecordId: "A", expectedModifiedTime: "2026-11-16T10:00:00Z"},
        {crmGuestRecordId: "B", expectedModifiedTime: "2026-11-16T10:00:00Z"},
        {crmGuestRecordId: "C", expectedModifiedTime: "2026-11-16T10:00:00Z", expectedIdentityId: "I1"},
        {crmGuestRecordId: "D", expectedModifiedTime: "2026-11-16T10:00:00Z"}
    ];
    map<json>[] crm = [
        {"id": "A", "Modified_Time": "2026-11-16T13:00:00+03:00"},
        {"id": "B", "Modified_Time": "2026-11-16T10:00:01Z"},
        {"id": "C", "Modified_Time": "2026-11-16T10:00:00Z", "Guest_Identity": {"id": "I2"}}
    ];
    FreshnessProblem[] p = freshnessProblemsOf(toCheck, crm);
    test:assertEquals(p, [
                {crmGuestRecordId: "B", reason: "MODIFIED_TIME_CHANGED"},
                {crmGuestRecordId: "C", reason: "IDENTITY_LINK_CHANGED"},
                {crmGuestRecordId: "D", reason: "RECORD_MISSING"}
            ]);
    test:assertEquals(freshnessProblemsOf("x", crm).length(), 0);
    test:assertTrue(sameInstant("2026-11-16T10:00", "2026-11-16T10:00:00Z"));
    test:assertFalse(sameInstant("garbage", "2026-11-16T10:00:00Z"));
}

@test:Config {}
function dlqRecordHasNoPersonalData() {
    map<json> d = dlqEventOf({
                                 eventId: "E1",
                                 correlationId: "C1",
                                 crmGuestRecordId: "G1",
                                 idempotencyKey: "K",
                                 firstName: "Secret"
                             }, "t", "CRM_UPDATE", "CRM_UPDATE_FAILED", 500, true, 5, "2026-11-16T10:00:00+00:00", "IDDEC-1");
    test:assertEquals(d["originalEventId"], "E1");
    test:assertEquals(d["httpStatus"], 500);
    test:assertEquals(d["decisionId"], "IDDEC-1");
    test:assertEquals(d["idempotencyKey"], "K");
    test:assertEquals((<string>d["payloadHash"]).length(), 64);
    test:assertFalse(d.toJsonString().includes("Secret"));
    map<json> bare = dlqEventOf({}, "t", "S", "E", (), false, 1, "x", "");
    test:assertFalse(bare.hasKey("decisionId"));
    test:assertFalse(bare.hasKey("httpStatus"));
    test:assertEquals(masked("5725767000012345678"), "…5678");
    test:assertEquals(masked("12"), "****");
    test:assertEquals(text(12), "12");
    test:assertEquals(text(()), "");
    test:assertEquals(pick({a: {b: 1}}, "a", "b"), 1);
    test:assertEquals(pick(1, "a"), ());
    test:assertTrue(now().endsWith("+00:00"));
}

isolated function ctxOf(json c) returns string =>
    re `=+$`.replaceAll(re `/`.replaceAll(re `\+`.replaceAll(array:toBase64(c.toJsonString().toBytes()), "-"), "_"), "");

@test:Config {}
function reviewerAuthentication() returns error? {
    string secret = "s3cret";
    string ctx = ctxOf({userId: "U1", roles: [ROLE_REVIEWER], exp: 1100});
    string sig = check signatureOf(ctx, secret);
    Reviewer r = check reviewerOf(ctx, sig.toUpperAscii(), secret, 1000, 300);
    test:assertEquals(r.userId, "U1");
    test:assertTrue(mayDecide(r, "CONFIRM_SAME_PERSON"));
    test:assertFalse(mayDecide(r, "REVERSE_DECISION"));
    test:assertTrue(mayView(r));
    test:assertTrue(mayDecide({userId: "S", roles: [ROLE_SUPERVISOR], exp: 1}, "REVERSE_DECISION"));
    test:assertFalse(mayDecide({userId: "A", roles: ["IDENTITY_AUDIT"], exp: 1}, "DEFER"));
    test:assertTrue(mayView({userId: "A", roles: ["IDENTITY_AUDIT"], exp: 1}));
    test:assertEquals((<error>reviewerOf(ctx, sig, "", 1000, 300)).message(), "REVIEW_AUTH_NOT_CONFIGURED");
    test:assertEquals((<error>reviewerOf("", sig, secret, 1000, 300)).message(), "REVIEWER_CONTEXT_MISSING");
    test:assertEquals((<error>reviewerOf(ctx, "00" + sig.substring(2), secret, 1000, 300)).message(), "REVIEWER_SIGNATURE_INVALID");
    test:assertEquals((<error>reviewerOf(ctx, "ab", secret, 1000, 300)).message(), "REVIEWER_SIGNATURE_INVALID");
    test:assertEquals((<error>reviewerOf(ctx, sig, secret, 1200, 300)).message(), "REVIEWER_CONTEXT_EXPIRED");
    test:assertEquals((<error>reviewerOf(ctx, sig, secret, 100, 300)).message(), "REVIEWER_CONTEXT_EXPIRED");
    string blank = ctxOf({userId: " ", roles: [], exp: 1100});
    test:assertEquals((<error>reviewerOf(blank, check signatureOf(blank, secret), secret, 1000, 300)).message(),
            "REVIEWER_CONTEXT_INVALID");
}

@test:Config {}
function workbenchReviewerAndPermissions() returns error? {
    Reviewer r = check trustedReviewerOf("Bearer tok", " Z1 ", "IDENTITY_REVIEWER, CRM_ADMINISTRATOR", "tok");
    test:assertEquals(r.userId, "Z1");
    test:assertEquals(r.roles, ["IDENTITY_REVIEWER", "CRM_ADMINISTRATOR"]);
    test:assertTrue(mayComment(r));
    test:assertTrue(mayAssign(r, "Z1"));
    test:assertFalse(mayAssign(r, "Z2"));
    test:assertTrue(mayAssign({userId: "S", roles: [ROLE_SUPERVISOR], exp: 0}, "Z2"));
    test:assertFalse(mayComment({userId: "A", roles: [ROLE_AUDIT], exp: 0}));
    test:assertTrue(mayView({userId: "A", roles: [ROLE_AUDIT], exp: 0}));
    test:assertEquals((<error>trustedReviewerOf("Bearer x", "Z1", "", "tok")).message(), "REVIEWER_TOKEN_INVALID");
    test:assertEquals((<error>trustedReviewerOf("Bearer tok", "", "", "tok")).message(), "REVIEWER_CONTEXT_MISSING");
    test:assertEquals((<error>trustedReviewerOf("Bearer tok", "Z1", "", "")).message(), "REVIEW_AUTH_NOT_CONFIGURED");
    test:assertEquals(withoutPersonalDetails("call +966 55 123 4567 or mail a.b@x.example, passport 12345678; same DOB"),
            "call [removed] or mail [removed], passport [removed]; same DOB");
    test:assertEquals(withoutPersonalDetails("same person, case 12"), "same person, case 12");
}
