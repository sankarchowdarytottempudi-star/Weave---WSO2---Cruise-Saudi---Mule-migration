// Review API and webhook scenarios (plan 21.3: open = zero CRM calls, unchanged submit = exactly one
// CRM read, changed CRM = REVIEW_DATA_CHANGED).

import guest_identity_integration.core;

import ballerina/test;

final core:Reviewer reviewer = {userId: "U-1", roles: [core:ROLE_REVIEWER], exp: 9999999999};

isolated function reviewSetup() returns [MemPython, MemCrm, MemBus, Deps] {
    MemPython p = new;
    MemCrm c = new;
    MemBus b = new;
    c.put("Contacts", {"id": "G1", "First_Name": "A", "Modified_Time": "2026-11-16T10:00:00+00:00"});
    c.put("Contacts", {"id": "G2", "First_Name": "B", "Modified_Time": "2026-11-16T12:40:00+03:00"});
    return [p, c, b, {python: p, crm: c, bus: b}];
}

isolated function submission(string action = "CONFIRM_SAME_PERSON") returns map<json> => {
    action,
    selectedIdentityId: "I200",
    comment: "same passport",
    idempotencyKey: "idem-1",
    versionsShown: [{crmGuestRecordId: "G1", crmModifiedTime: "2026-11-16T10:00:00+00:00"}]
};

@test:Config {}
function openingACaseMakesZeroCrmCalls() {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = reviewSetup();
    Answer a = openCase(d, reviewer, "RC-1", "C1");
    test:assertEquals(a.status, 200);
    test:assertEquals(c.total(), 0);
    test:assertEquals(p.count("GET /v1/review-cases/RC-1"), 1);
    test:assertEquals(core:pick(a.body, "reviewer"), "U-1");
}

@test:Config {}
function unchangedSubmitReadsCrmExactlyOnce() {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = reviewSetup();
    Answer a = submitDecision(d, reviewer, "RC-1", submission(), "C2");
    test:assertEquals(a.status, 200, a.body.toJsonString());
    test:assertEquals(core:pick(a.body, "state"), "REVIEW_COMMITTED");
    test:assertEquals(c.count("GET "), 1, "exactly one CRM read");
    test:assertEquals(c.count("PUT /crm/v6/Guest_Identities"), 1); // alias retired
    test:assertEquals(c.count("PUT /crm/v6/Contacts"), 1);
    test:assertEquals(c.count("POST /crm/v6/Identity_Review_Cases/upsert"), 1);
    test:assertEquals(p.count("POST /v1/review-decisions/RD-1/commit"), 1);
    map<json> guest = c.recordOf("Contacts", "G1") ?: {};
    test:assertEquals(guest["Identity_Status"], "CONFIRMED_SAME_PERSON");
    test:assertEquals(guest["Guest_Identity"], {"id": "I200"});
}

@test:Config {}
function crmChangedBeforeSubmitAnswersReviewDataChanged() {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = reviewSetup();
    c.put("Contacts", {"id": "G2", "First_Name": "B2", "Modified_Time": "2026-11-16T11:00:00+00:00"});
    Answer a = submitDecision(d, reviewer, "RC-1", submission(), "C3");
    test:assertEquals(a.status, 409);
    test:assertEquals(core:pick(a.body, "code"), "REVIEW_DATA_CHANGED");
    test:assertEquals(core:pick(a.body, "changedRecords"), ["G2"]);
    test:assertEquals(c.count("GET "), 1);
    test:assertEquals(c.count("PUT "), 0, "CRM is not updated");
    test:assertEquals(c.count("POST "), 0);
    test:assertEquals(p.count("POST /v1/review-decisions/RD-1/freshness-failed"), 1);
}

@test:Config {}
function missingRecordIsAFreshnessFailureToo() {
    MemPython p = new;
    MemCrm c = new;
    Deps d = {python: p, crm: c, bus: new MemBus()};
    Answer a = submitDecision(d, reviewer, "RC-1", submission(), "C4");
    test:assertEquals(a.status, 409);
    test:assertEquals(p.count("POST /v1/review-decisions/RD-1/fail"), 1);
}

@test:Config {}
function crmWriteFailureLeavesTheDecisionPending() {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = reviewSetup();
    c.setWriteFailures(1);
    Answer a = submitDecision(d, reviewer, "RC-1", submission(), "C5");
    test:assertEquals(a.status, 502);
    test:assertEquals(core:pick(a.body, "code"), "REVIEW_CRM_UPDATE_PENDING");
    test:assertEquals(p.count("POST /v1/review-decisions/RD-1/fail"), 1);
    test:assertEquals(p.count("POST /v1/review-decisions/RD-1/commit"), 0);
}

@test:Config {}
function commitPendingAnswers202() {
    [MemPython, MemCrm, MemBus, Deps] [p, _, _, d] = reviewSetup();
    p.setCommitFailures(100);
    Answer a = submitDecision(d, reviewer, "RC-1", submission(), "C6");
    test:assertEquals(a.status, 202);
    test:assertEquals(core:pick(a.body, "state"), "REVIEW_CRM_UPDATE_PENDING");
}

@test:Config {}
function unknownPatchKeyIsRefused() {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = reviewSetup();
    p.setPatch({"identityStatus": "X", "somethingNew": 1});
    Answer a = submitDecision(d, reviewer, "RC-1", submission(), "C7");
    test:assertEquals(a.status, 502);
    test:assertEquals(c.count("PUT "), 0);
}

@test:Config {}
function reviewerRolesAndInputAreChecked() {
    [MemPython, MemCrm, MemBus, Deps] [_, c, _, d] = reviewSetup();
    test:assertEquals(submitDecision(d, reviewer, "RC-1", submission("REVERSE_DECISION"), "C").status, 403);
    test:assertEquals(submitDecision(d, reviewer, "RC-1", {action: "DEFER"}, "C").status, 400);
    test:assertEquals(openCase(d, {userId: "U", roles: ["OTHER"], exp: 1}, "RC-1", "C").status, 403);
    test:assertEquals(c.total(), 0);
}

@test:Config {}
function pythonDownOnSubmitAnswers503() {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = reviewSetup();
    p.setUnreachable(true);
    test:assertEquals(submitDecision(d, reviewer, "RC-1", submission(), "C").status, 503);
    test:assertEquals(openCase(d, reviewer, "RC-1", "C").status, 503);
    test:assertEquals(c.total(), 0);
}

@test:Config {}
function webhookPublishesTheRightTopic() {
    [MemPython, MemCrm, MemBus, Deps] [_, _, b, d] = reviewSetup();
    map<json> rec = {"id": "G7", "Modified_Time": "2026-11-16T10:00:00+00:00", "First_Name": "X"};
    test:assertEquals(acceptGuestEvent(d, {eventType: "created", 'record: rec}, "C").status, 202);
    test:assertEquals(acceptGuestEvent(d, {eventType: "updated", 'record: rec}, "C").status, 202);
    json[] ev = b.onTopic("guest.identity.evaluation.requested.v1");
    json[] re = b.onTopic("guest.identity.reevaluation.requested.v1");
    test:assertEquals(ev.length(), 1);
    test:assertEquals(re.length(), 1);
    test:assertEquals(core:pick(ev[0], "sourceSystem"), "CRM_DIRECT");
    test:assertEquals(core:pick(ev[0], "sourceRecordId"), "G7");
    // a ready event from the ingress passes as it is
    test:assertEquals(acceptGuestEvent(d, guestEvent("G8", "2026-11-16T10:00:00+00:00"), "C").status, 202);
    test:assertEquals(b.onTopic("guest.identity.evaluation.requested.v1").length(), 2);
    test:assertEquals(acceptGuestEvent(d, {eventType: "created"}, "C").status, 400);
    test:assertEquals(acceptGuestEvent(d, [], "C").status, 400);
    test:assertEquals(acceptGuestEvent(d, {eventType: "created", 'record: {"id": "G9"}}, "C").status, 400);
    b.setDown(true);
    test:assertEquals(acceptGuestEvent(d, {eventType: "created", 'record: rec}, "C").status, 503);
}
