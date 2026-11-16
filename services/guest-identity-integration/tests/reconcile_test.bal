// Reconciliation (plan 17) against the stand-ins.

import guest_identity_integration.core;

import ballerina/test;

@test:Config {}
function reconcileRepublishesAndCommitsAndAdvancesTheWatermark() returns error? {
    MemPython p = new;
    MemCrm c = new;
    MemBus b = new;
    Deps d = {python: p, crm: c, bus: b};
    // a decision CRM already shows but Python has not committed (commit failed earlier)
    _ = check handleEvent({python: p, crm: c, bus: b}, "guest.identity.evaluation.requested.v1",
                          guestEvent("G1", "2026-11-16T10:00:00+00:00"));
    p.setCommitFailures(0);
    json[] delta = [
        {
            "id": "G1",
            "Modified_Time": "2026-11-16T12:00:00+00:00",
            "Identity_Status": "NEW_IDENTITY_CREATED",
            "Identity_Decision_ID": "IDDEC-1",
            "Guest_Identity": {"id": "Z1001"},
            "Source_System": "SEAWARE",
            "Client_ID": "S-G1"
        },
        {"id": "G2", "Modified_Time": "2026-11-16T13:00:00+00:00", "Identity_Status": "PENDING_IDENTITY"}
    ];
    json[] pending = [{"id": "G3", "Modified_Time": "2026-11-15T13:00:00+00:00", "Identity_Status": "PENDING_IDENTITY"}];
    c.setCoqlPages([delta, pending]);
    MemoryState st = new;
    ReconcileReport rep = check runReconcile(d, st);
    test:assertTrue(rep.ran);
    test:assertEquals(rep.deltaRecords, 2);
    test:assertEquals(rep.reevaluationsPublished, 1);
    test:assertEquals(rep.pendingRepublished, 1);
    test:assertEquals(rep.failures, 0);
    test:assertTrue(rep.watermarkAdvanced);
    test:assertEquals(check st.get("gir:reconcile:watermark"), "2026-11-16T13:00:00+00:00");
    json[] re = b.onTopic("guest.identity.reevaluation.requested.v1");
    test:assertEquals(core:pick(re[0], "sourceSystem"), "SEAWARE");
    test:assertEquals(core:pick(re[0], "currentIdentityId"), "Z1001");
    test:assertEquals(c.count("PUT "), 1, "reconciliation itself never writes identities to CRM");
}

@test:Config {}
function reconcileCommitsAPendingDecision() returns error? {
    MemPython p = new;
    MemCrm c = new;
    MemBus b = new;
    Deps d = {python: p, crm: c, bus: b};
    p.setCommitFailures(1000);
    _ = check handleEvent(d, "guest.identity.evaluation.requested.v1", guestEvent("G1", "2026-11-16T10:00:00+00:00"));
    test:assertEquals(p.state("IDDEC-1"), "DECIDED_PENDING_CRM");
    p.setCommitFailures(0);
    c.setCoqlPages([
        [
            {
                "id": "G1",
                "Modified_Time": "2026-11-16T12:00:00+00:00",
                "Identity_Status": "NEW_IDENTITY_CREATED",
                "Identity_Decision_ID": "IDDEC-1",
                "Guest_Identity": {"id": "Z1001"}
            }
        ]
    ]);
    ReconcileReport rep = check runReconcile(d, new MemoryState());
    test:assertEquals(rep.commitsRetried, 1);
    test:assertEquals(p.state("IDDEC-1"), "COMMITTED");
    test:assertEquals(p.pairsReserved(), 1);
}

@test:Config {}
function reconcileHoldsTheWatermarkOnFailureAndHonoursTheLock() returns error? {
    MemPython p = new;
    MemCrm c = new;
    MemBus b = new;
    b.setDown(true);
    Deps d = {python: p, crm: c, bus: b};
    c.setCoqlPages([
        [
            {
                "id": "G5",
                "Modified_Time": "2026-11-16T12:00:00+00:00",
                "Identity_Status": "NEW_IDENTITY_CREATED",
                "Guest_Identity": {"id": "Z9"}
            }
        ]
    ]);
    MemoryState st = new;
    ReconcileReport rep = check runReconcile(d, st);
    test:assertEquals(rep.failures, 1);
    test:assertFalse(rep.watermarkAdvanced);
    test:assertEquals(check st.get("gir:reconcile:watermark"), ());
    _ = check st.tryLock("gir:reconcile:lock", 60);
    ReconcileReport skipped = check runReconcile(d, st);
    test:assertEquals(skipped.skippedReason, "LOCKED");
}

@test:Config {}
function reconcileStopsWhenCrmCannotBeQueried() returns error? {
    MemPython p = new;
    Deps d = {python: p, crm: new DownCrm(), bus: new MemBus()};
    MemoryState st = new;
    ReconcileReport rep = check runReconcile(d, st);
    test:assertEquals(rep.failures, 1);
    test:assertFalse(rep.watermarkAdvanced);
    // the lock was released
    test:assertTrue(check st.tryLock("gir:reconcile:lock", 60));
}

isolated class DownCrm {
    *CrmApi;

    isolated function call(string method, string zohoPath, map<string> query, json body, string correlationId)
            returns Reply|error => error("unreachable");
}

@test:Config {}
function backoffDoublesAndIsCapped() {
    test:assertEquals(backoffOf(1), 0.01d);
    test:assertEquals(backoffOf(2), 0.02d);
    test:assertEquals(backoffOf(5), 0.04d);
}
