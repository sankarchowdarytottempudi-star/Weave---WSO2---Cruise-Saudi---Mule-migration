// Workbench contract (Factory BFF): queue, history, assignment, comments - Python only, no CRM.

import guest_identity_integration.core;

import ballerina/test;

final core:Reviewer supervisor = {userId: "S-1", roles: [core:ROLE_SUPERVISOR], exp: 0};
final core:Reviewer auditor = {userId: "A-1", roles: [core:ROLE_AUDIT], exp: 0};

@test:Config {}
function queueHistoryAssignmentCommentsNeverCallCrm() {
    [MemPython, MemCrm, MemBus, Deps] [p, c, _, d] = reviewSetup();
    Answer q = listCases(d, reviewer, {"kind": "FOUR_FIELD_REVIEW", "assignee": "U-1", "evil": "x"}, "C");
    test:assertEquals(q.status, 200);
    string query = core:text(core:pick(q.body, "query"));
    test:assertTrue(query.includes("kind=FOUR_FIELD_REVIEW") && query.includes("assignee=U-1"));
    test:assertFalse(query.includes("evil"));
    test:assertEquals(caseHistory(d, auditor, "RC-1", "C").status, 200);
    Answer take = assignCase(d, reviewer, "RC-1", {assigneeId: "U-1", assignedBy: "someone-else"}, "C");
    test:assertEquals(take.status, 200);
    test:assertEquals(core:pick(take.body, "assignedBy"), "U-1", "assignedBy comes from the session");
    test:assertEquals(assignCase(d, reviewer, "RC-1", {assigneeId: "U-2"}, "C").status, 403);
    test:assertEquals(assignCase(d, supervisor, "RC-1", {assigneeId: "U-2"}, "C").status, 200);
    test:assertEquals(assignCase(d, supervisor, "RC-1", {}, "C").status, 400);
    Answer note = commentCase(d, reviewer, "RC-1", {authorId: "x", text: "phone +966 55 123 4567 matches"}, "C");
    test:assertEquals(note.status, 200);
    test:assertEquals(core:pick(note.body, "authorId"), "U-1");
    test:assertEquals(core:pick(note.body, "text"), "phone [removed] matches");
    test:assertEquals(commentCase(d, auditor, "RC-1", {text: "x"}, "C").status, 403);
    test:assertEquals(commentCase(d, reviewer, "RC-1", {text: ""}, "C").status, 400);
    test:assertEquals(listCases(d, {userId: "N", roles: [], exp: 0}, {}, "C").status, 403);
    test:assertEquals(caseHistory(d, {userId: "N", roles: [], exp: 0}, "RC-1", "C").status, 403);
    test:assertEquals(c.total(), 0);
    test:assertEquals(p.count("POST /v1/review-cases/RC-1/assignment"), 2);
}
