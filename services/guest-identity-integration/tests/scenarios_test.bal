// Plan 21.3 scenarios against the stand-ins, plus the failure paths of the worker.

import guest_identity_integration.core;

import ballerina/test;

const string T1 = "2026-11-16T10:00:00+00:00";
const string T2 = "2026-11-16T11:00:00+00:00";

isolated function fresh() returns [MemPython, MemCrm, MemBus, Deps] {
    MemPython p = new;
    MemCrm c = new;
    MemBus b = new;
    c.put("Contacts", {"id": "G1", "Modified_Time": T1});
    return [p, c, b, {python: p, crm: c, bus: b}];
}

@test:Config {}
function sourceGuestEndToEnd() returns error? {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = fresh();
    Outcome o = check handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", T1));
    test:assertEquals(o.result, "DONE");
    test:assertEquals(p.pairsReserved(), 1);
    test:assertEquals(c.count("POST /crm/v6/Guest_Identities/upsert"), 1);
    test:assertEquals(c.count("PUT /crm/v6/Contacts"), 1);
    map<json> guest = c.recordOf("Contacts", "G1") ?: {};
    test:assertEquals(guest["Identity_Status"], "NEW_IDENTITY_CREATED");
    test:assertEquals(guest["Global_Guest_ID"], "01JTESTGLOBAL0000000000001");
    test:assertEquals(guest["Aroya_Loyalty_ID"], "1200000001");
    test:assertTrue(guest["Guest_Identity"] is map<json>);
    test:assertEquals(p.state("IDDEC-1"), "COMMITTED");
}

@test:Config {}
function duplicateEventAppliesNothingTwice() returns error? {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = fresh();
    _ = check handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", T1));
    int writes = c.total();
    Outcome o = check handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", T1));
    test:assertEquals(o.result, "DONE");
    test:assertEquals(c.total(), writes, "a duplicate event must not touch CRM");
    test:assertEquals(p.pairsReserved(), 1);
    test:assertEquals(p.count("POST /v1/guest-identities/decisions/IDDEC-1/commit"), 1);
}

@test:Config {}
function crmFailureRetriesTheSamePair() returns error? {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = fresh();
    c.setWriteFailures(1);
    Outcome o = check handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", T1));
    test:assertEquals(o.result, "DONE");
    test:assertEquals(p.count("POST /v1/guest-identities/decisions/IDDEC-1/fail"), 1);
    test:assertEquals(p.pairsReserved(), 1, "never a second pair");
    test:assertEquals(p.count("POST /v1/guest-identities/evaluate"), 2);
    map<json> guest = c.recordOf("Contacts", "G1") ?: {};
    test:assertEquals(guest["Global_Guest_ID"], "01JTESTGLOBAL0000000000001");
    test:assertEquals(p.state("IDDEC-1"), "COMMITTED");
}

@test:Config {}
function commitFailureAfterCrmSuccessRetriesOnlyTheCommit() returns error? {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = fresh();
    p.setCommitFailures(2);
    Outcome o = check handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", T1));
    test:assertEquals(o.result, "DONE");
    test:assertEquals(c.count("PUT /crm/v6/Contacts"), 1, "CRM is not written again for a commit retry");
    test:assertEquals(p.count("POST /v1/guest-identities/decisions/IDDEC-1/commit"), 3);
    test:assertEquals(p.pairsReserved(), 1);
}

@test:Config {}
function commitThatNeverSucceedsEndsInTheDlqWithTheSamePair() returns error? {
    [MemPython, MemCrm, MemBus, Deps] [p, c, b, d] = fresh();
    p.setCommitFailures(1000);
    Outcome o = check handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", T1));
    test:assertEquals(o.result, "RETRY");
    test:assertEquals(o.stage, "PYTHON_COMMIT");
    json[] dead = b.onTopic("guest.identity.processing.dlq.v1");
    test:assertEquals(dead.length(), 1);
    test:assertEquals(core:pick(dead[0], "failureStage"), "PYTHON_COMMIT");
    test:assertEquals(core:pick(dead[0], "retryable"), true);
    test:assertEquals(core:pick(dead[0], "decisionId"), "IDDEC-1");
    test:assertFalse(dead[0].toJsonString().includes("Test"), "no personal data in the DLQ");
    test:assertEquals(p.pairsReserved(), 1);
    // CRM writes repeat with the same values on each attempt, never a different pair
    map<json> guest = c.recordOf("Contacts", "G1") ?: {};
    test:assertEquals(guest["Global_Guest_ID"], "01JTESTGLOBAL0000000000001");
}

@test:Config {}
function outOfOrderEventIsRejectedWithoutCrmWrites() returns error? {
    [MemPython, MemCrm, MemBus, Deps] [_, c, _, d] = fresh();
    _ = check handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", T2));
    int before = c.total();
    Outcome o = check handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", T1));
    test:assertEquals(o.result, "DONE");
    test:assertEquals(o.errorCode, "STALE_CRM_EVENT");
    test:assertEquals(c.total(), before);
}

@test:Config {}
function pythonDownGoesToTheDlqAfterBoundedRetries() returns error? {
    [MemPython, MemCrm, MemBus, Deps] [p, c, b, d] = fresh();
    p.setUnreachable(true);
    Outcome o = check handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", T1));
    test:assertEquals(o.result, "RETRY");
    test:assertEquals(p.count("POST /v1/guest-identities/evaluate"), 3);
    test:assertEquals(b.onTopic("guest.identity.processing.dlq.v1").length(), 1);
    test:assertEquals(c.total(), 0, "no IDs are invented when Python is down");
}

@test:Config {}
function pythonRecoversWithinTheRetries() returns error? {
    [MemPython, MemCrm, MemBus, Deps] [p, _, b, d] = fresh();
    p.setEvaluateFailures(2);
    Outcome o = check handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", T1));
    test:assertEquals(o.result, "DONE");
    test:assertEquals(b.onTopic("guest.identity.processing.dlq.v1").length(), 0);
}

@test:Config {}
function dlqUnreachableIsReportedSoTheOffsetIsNotCommitted() {
    [MemPython, MemCrm, MemBus, Deps] [p, _, b, d] = fresh();
    p.setUnreachable(true);
    b.setDown(true);
    Outcome|error o = handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", T1));
    test:assertTrue(o is error);
}

@test:Config {}
function invalidAndUnparsableEventsGoStraightToTheDlq() returns error? {
    [MemPython, MemCrm, MemBus, Deps] [p, _, b, d] = fresh();
    map<json> e = guestEvent("G1", T1);
    e["crmModifiedTime"] = "";
    Outcome o = check handleEvent(d, "guest.identity.evaluation.requested.v1", e);
    test:assertEquals(o.result, "DLQ");
    test:assertEquals(o.stage, "VALIDATION");
    Outcome raw = check handleRaw(d, "guest.identity.evaluation.requested.v1", "not json".toBytes());
    test:assertEquals(raw.errorCode, "NOT_JSON");
    Outcome ok = check handleRaw(d, "guest.identity.evaluation.requested.v1", guestEvent("G9", T1).toJsonString().toBytes());
    test:assertEquals(ok.result, "DONE");
    test:assertEquals(b.onTopic("guest.identity.processing.dlq.v1").length(), 2);
    test:assertEquals(p.count("POST /v1/guest-identities/evaluate"), 1);
}

@test:Config {}
function existingIdentityIsKeptWithoutCrmUpdate() returns error? {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = fresh();
    Outcome o = check handleEvent(d, "guest.identity.reevaluation.requested.v1",
            guestEvent("G1", T1, "01JEXISTING000000000000000"));
    test:assertEquals(o.result, "DONE");
    test:assertEquals(c.total(), 0);
    test:assertEquals(p.count("POST /v1/guest-identities/re-evaluate"), 1);
}

@test:Config {}
function aDifferentPairForAGuestWithIdsIsRefused() {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = fresh();
    map<json> decision = {
        decisionId: "IDDEC-77",
        decision: "CREATE_NEW_IDENTITY",
        globalId: "01JOTHER",
        loyaltyId: "1299999999",
        processingState: "DECIDED_PENDING_CRM",
        crmUpdateRequired: true
    };
    Outcome o = applyDecision(d, guestEvent("G1", T1, "01JEXISTING000000000000000"), decision, "CORR-X");
    test:assertEquals(o.result, "DLQ");
    test:assertEquals(o.errorCode, "ID_CHANGE_REFUSED");
    test:assertEquals(c.total(), 0);
    test:assertEquals(p.count("POST /v1/guest-identities/decisions/IDDEC-77/fail"), 1);
}

@test:Config {}
function decisionStatesThatEndTheEvent() {
    [MemPython, MemCrm, MemBus, Deps] [_, c, _, d] = fresh();
    test:assertEquals(applyDecision(d, guestEvent("G1", T1), {decisionId: "IDDEC-5", processingState: "FAILED"}, "C").result, "DLQ");
    test:assertEquals(applyDecision(d, guestEvent("G1", T1), {processingState: "DECIDED_PENDING_CRM"}, "C").errorCode,
            "DECISION_WITHOUT_ID");
    test:assertEquals(applyDecision(d, guestEvent("G1", T1), {
                                                                 decisionId: "IDDEC-6",
                                                                 decision: "EXCLUDED_NON_DIRECT",
                                                                 crmUpdateRequired: false,
                                                                 processingState: "COMMITTED"
                                                             }, "C").result, "DONE");
    test:assertEquals(c.total(), 0);
}

@test:Config {}
function reviewDecisionWithACaseIsMirrored() returns error? {
    [MemPython, MemCrm, MemBus, Deps] [_, c, _, d] = fresh();
    map<json> decision = {
        decisionId: "IDDEC-8",
        decision: "CREATE_PROVISIONAL_IDENTITY",
        decisionType: "FOUR_FIELD",
        identityStatus: "NEW_IDENTITY_PENDING_REVIEW",
        globalId: "01JPROV",
        loyaltyId: "1200000088",
        provisional: true,
        reviewRequired: true,
        reviewCaseId: "RC-8",
        reviewPriority: "HIGH",
        ruleVersion: "1.0",
        reasonCodes: ["FOUR_FIELD"],
        crmUpdateRequired: true,
        processingState: "DECIDED_PENDING_CRM"
    };
    Outcome o = applyDecision(d, guestEvent("G1", T1), decision, "C");
    test:assertEquals(o.result, "DONE");
    test:assertEquals(c.count("POST /crm/v6/Identity_Review_Cases/upsert"), 1);
}
