"""DB-backed manual review (9.6, 9.7, 14.4, 21.5) - and proof that review uses PostgreSQL only."""
import socket

import pytest
from sqlalchemy import text

from tests.integration.conftest import URL, commit, established, evaluate, event

REVIEWER = {"X-Reviewer-Id": "CRMUSER-77", "X-Reviewer-Roles": "IDENTITY_REVIEWER", "X-Correlation-Id": "C-rev"}
SUPERVISOR = {"X-Reviewer-Id": "CRMUSER-77", "X-Reviewer-Roles": "IDENTITY_SUPERVISOR", "X-Correlation-Id": "C-rev"}


def four_field_case(client):
    base = established(client, guest="R200", email="ff@gir-synthetic.invalid")
    d = evaluate(client, event(guest="R100", dob="1986-05-10", email="ff@gir-synthetic.invalid"))
    commit(client, d)                                  # provisional pair committed to CRM
    return base, d


def versions(client, case_id, headers=REVIEWER):
    c = client.get(f"/v1/review-cases/{case_id}", headers=headers).json()
    return c, [{"crmGuestRecordId": g["crmGuestRecordId"], "crmModifiedTime": g["crmModifiedTime"]}
               for g in [c["incoming"]] + c["candidates"]]


def prepare(client, case_id, action, vs, headers=REVIEWER, key="k1", **extra):
    body = {"caseId": case_id, "reviewerId": headers["X-Reviewer-Id"], "action": action, "versionsShown": vs,
            "idempotencyKey": key, **extra}
    return client.post(f"/v1/review-cases/{case_id}/decision-preparations", json=body, headers=headers)


def test_get_case_returns_db_projection_with_display_for_reviewers_only(client):
    base, d = four_field_case(client)
    case, vs = versions(client, d["reviewCaseId"])
    assert case["caseStatus"] == "REVIEW_OPEN" and case["kind"] == "FOUR_FIELD_REVIEW" and case["slaBusinessDays"] == 2
    assert case["incoming"]["display"]["firstName"] == "Testfirst"
    cand = case["candidates"][0]
    assert cand["crmGuestRecordId"] == "R200" and cand["fieldResults"]["dateOfBirth"] == "CONFLICT"
    assert cand["identity"]["globalId"] == base["globalId"]
    audit = client.get(f"/v1/review-cases/{d['reviewCaseId']}",
                       headers={**REVIEWER, "X-Reviewer-Roles": "AUDIT_REPORTING"}).json()
    assert "display" not in audit["incoming"] and "globalId" not in audit["candidates"][0]["identity"]
    admin = client.get(f"/v1/review-cases/{d['reviewCaseId']}", headers={**REVIEWER, "X-Reviewer-Roles": "CRM_ADMINISTRATOR"})
    assert admin.status_code == 200 and "display" not in admin.json()["incoming"]
    nobody = client.get(f"/v1/review-cases/{d['reviewCaseId']}", headers={**REVIEWER, "X-Reviewer-Roles": "OTHER"})
    assert nobody.status_code == 403
    assert client.get(f"/v1/review-cases/{d['reviewCaseId']}", headers={"X-Reviewer-Id": "u"}).status_code == 422
    assert client.get("/v1/review-cases/RC-NONE", headers=REVIEWER).status_code == 404


def test_review_uses_postgresql_only(client, monkeypatch):
    """Opening a case and preparing a decision make zero non-database network connections (21.8)."""
    from sqlalchemy.engine import make_url
    u = make_url(URL)
    allowed = {(u.host, u.port or 5432)}
    seen = []
    real = socket.socket.connect

    def spy(self, addr):
        seen.append(addr)
        return real(self, addr)
    _, d = four_field_case(client)
    monkeypatch.setattr(socket.socket, "connect", spy)
    case, vs = versions(client, d["reviewCaseId"])
    r = prepare(client, d["reviewCaseId"], "CONFIRM_DIFFERENT_PEOPLE", vs)
    assert r.status_code == 200
    others = [a for a in seen if not (isinstance(a, tuple) and (a[0], a[1]) in allowed)]
    assert others == []


def test_confirm_same_person_prepare_commit(client, db):
    base, d = four_field_case(client)
    case, vs = versions(client, d["reviewCaseId"])
    target = case["candidates"][0]["identityId"]
    p = prepare(client, d["reviewCaseId"], "CONFIRM_SAME_PERSON", vs, selectedIdentityId=target)
    assert p.status_code == 200, p.text
    prep = p.json()
    assert prep["state"] == "REVIEW_DECISION_PREPARED" and prep["crmPatch"]["identityStatus"] == "CONFIRMED_SAME_PERSON"
    assert prep["crmPatch"]["guestIdentityId"] == base["crmIdentityRecordId"]
    assert prep["crmPatch"]["aliasIdentityId"] == "CRMID-" + d["decisionId"]
    assert {r["crmGuestRecordId"] for r in prep["crmRecordsToCheck"]} == {"R100", "R200"}
    assert prep["compareFields"][-1] == "guestIdentityId"
    again = prepare(client, d["reviewCaseId"], "CONFIRM_SAME_PERSON", vs, selectedIdentityId=target)
    assert again.json()["reviewDecisionId"] == prep["reviewDecisionId"]          # idempotent
    done = client.post(f"/v1/review-decisions/{prep['reviewDecisionId']}/commit", json={}).json()
    assert done["state"] == "REVIEW_COMMITTED"
    assert client.post(f"/v1/review-decisions/{prep['reviewDecisionId']}/commit", json={}).status_code == 200
    with db.connect() as c:
        assert c.execute(text("SELECT lifecycle_status FROM identity_projection WHERE identity_id=:i"),
                         {"i": d["identityId"]}).scalar() == "ALIAS"
        assert str(c.execute(text("SELECT identity_id FROM guest_match_index WHERE crm_guest_record_id='R100'")).scalar()) == target
    closed = client.get(f"/v1/review-cases/{d['reviewCaseId']}", headers=REVIEWER).json()
    assert closed["caseStatus"] == "REVIEW_COMMITTED"
    assert prepare(client, d["reviewCaseId"], "DEFER", vs, key="k2").status_code == 409


def test_version_changed_in_db_returns_review_data_changed(client):
    _, d = four_field_case(client)
    case, vs = versions(client, d["reviewCaseId"])
    evaluate(client, event(guest="R200", t="2026-11-16T13:00:00Z", email="ff@gir-synthetic.invalid",
                           kind="GUEST_IDENTITY_REEVALUATION_REQUESTED"), "/v1/guest-identities/re-evaluate")
    r = prepare(client, d["reviewCaseId"], "CONFIRM_DIFFERENT_PEOPLE", vs)
    assert r.status_code == 409 and r.json()["code"] == "REVIEW_DATA_CHANGED" and r.json()["changedRecords"] == ["R200"]


def test_freshness_failed_refreshes_projection_and_reopens(client, db):
    _, d = four_field_case(client)
    case, vs = versions(client, d["reviewCaseId"])
    prep = prepare(client, d["reviewCaseId"], "CONFIRM_DIFFERENT_PEOPLE", vs).json()
    snap = event(guest="R200", t="2026-11-16T14:00:00Z", phone="+1 202 555 0199", email="changed@gir-synthetic.invalid",
                 kind="GUEST_IDENTITY_REEVALUATION_REQUESTED")
    r = client.post(f"/v1/review-decisions/{prep['reviewDecisionId']}/freshness-failed", json={"snapshots": [snap]})
    assert r.status_code == 200 and r.json()["state"] == "REVIEW_DATA_CHANGED"
    case2, vs2 = versions(client, d["reviewCaseId"])
    assert case2["caseStatus"] == "REVIEW_DATA_CHANGED" and "CRM_FRESHNESS_CHECK_FAILED" in case2["reasonCodes"]
    assert case2["candidates"] == [] or case2["candidates"][0]["fieldResults"]["email"] != "EXACT"
    with db.connect() as c:
        assert c.execute(text("SELECT email_key FROM guest_match_index WHERE crm_guest_record_id='R200'")).scalar() \
            == "changed@gir-synthetic.invalid"
    assert client.post(f"/v1/review-decisions/{prep['reviewDecisionId']}/commit", json={}).status_code == 409


def test_different_people_household_defer_and_failures(client, db):
    _, d = four_field_case(client)
    case, vs = versions(client, d["reviewCaseId"])
    bad = prepare(client, d["reviewCaseId"], "CONFIRM_DIFFERENT_PEOPLE", vs, selectedIdentityId=d["identityId"])
    assert bad.status_code == 422
    assert prepare(client, d["reviewCaseId"], "DEFER", vs, key="d0").status_code == 422      # needs comment + date
    defer = prepare(client, d["reviewCaseId"], "DEFER", vs, key="d1", comment="waiting for passport",
                    followUpDate="2026-11-20").json()
    assert defer["crmPatch"]["followUpDate"] == "2026-11-20"
    f = client.post(f"/v1/review-decisions/{defer['reviewDecisionId']}/fail", json={"retryable": True, "errorCode": "T"})
    assert f.json()["state"] == "REVIEW_CRM_UPDATE_PENDING"
    client.post(f"/v1/review-decisions/{defer['reviewDecisionId']}/commit", json={})
    assert versions(client, d["reviewCaseId"])[0]["caseStatus"] == "REVIEW_OPEN"
    hh = prepare(client, d["reviewCaseId"], "CONFIRM_HOUSEHOLD", vs, key="h1").json()
    assert hh["crmPatch"]["householdWith"]
    t = client.post(f"/v1/review-decisions/{hh['reviewDecisionId']}/fail", json={"retryable": False, "errorCode": "X"})
    assert t.json()["state"] == "REVIEW_FAILED" and versions(client, d["reviewCaseId"])[0]["caseStatus"] == "REVIEW_OPEN"
    diff = prepare(client, d["reviewCaseId"], "CONFIRM_DIFFERENT_PEOPLE", vs, key="x1").json()
    client.post(f"/v1/review-decisions/{diff['reviewDecisionId']}/commit", json={})
    with db.connect() as c:
        assert c.execute(text("SELECT lifecycle_status FROM identity_projection WHERE identity_id=:i"),
                         {"i": d["identityId"]}).scalar() == "ACTIVE"


def test_reverse_requires_supervisor_and_idempotency_key_reuse_conflicts(client):
    _, d = four_field_case(client)
    case, vs = versions(client, d["reviewCaseId"])
    target = case["candidates"][0]["identityId"]
    assert prepare(client, d["reviewCaseId"], "REVERSE_DECISION", vs, selectedIdentityId=target).status_code == 403
    ok = prepare(client, d["reviewCaseId"], "REVERSE_DECISION", vs, headers=SUPERVISOR, key="rv", selectedIdentityId=target)
    assert ok.status_code == 200
    clash = prepare(client, d["reviewCaseId"], "DEFER", vs, headers=SUPERVISOR, key="rv", comment="c", followUpDate="2026-12-01")
    assert clash.status_code == 409 and clash.json()["code"] == "IDEMPOTENCY_CONFLICT"
    assert prepare(client, d["reviewCaseId"], "NOT_AN_ACTION", vs).status_code == 422
    other = client.post(f"/v1/review-cases/{d['reviewCaseId']}/decision-preparations", headers={**REVIEWER, "X-Reviewer-Id": "x"},
                        json={"caseId": d["reviewCaseId"], "reviewerId": "CRMUSER-77", "action": "DEFER", "versionsShown": vs,
                              "idempotencyKey": "o1", "comment": "c", "followUpDate": "2026-12-01"})
    assert other.status_code == 403        # body reviewerId differs from the asserted reviewer



def test_workbench_queue_history_assignment_comments(client):
    _, d = four_field_case(client)
    case_id = d["reviewCaseId"]
    q = client.get("/v1/review-cases", headers=REVIEWER).json()
    assert q["total"] == 1 and q["cases"][0]["caseId"] == case_id and q["cases"][0]["slaDueTime"]
    assert q["cases"][0]["candidateCount"] == 1 and not q["cases"][0]["overdue"]
    assert client.get("/v1/review-cases?kind=PAIR_REPAIR", headers=REVIEWER).json()["total"] == 0
    assert client.get("/v1/review-cases?assignee=unassigned", headers=REVIEWER).json()["total"] == 1
    # take it
    t = client.post(f"/v1/review-cases/{case_id}/assignment", headers=REVIEWER,
                    json={"assigneeId": "CRMUSER-77", "assignedBy": "CRMUSER-77"})
    assert t.status_code == 200
    assert client.get("/v1/review-cases?assignee=CRMUSER-77", headers=REVIEWER).json()["total"] == 1
    # hand-over needs a supervisor; assignedBy must be the caller
    assert client.post(f"/v1/review-cases/{case_id}/assignment", headers=REVIEWER,
                       json={"assigneeId": "OTHER-1", "assignedBy": "CRMUSER-77"}).status_code == 403
    assert client.post(f"/v1/review-cases/{case_id}/assignment", headers=SUPERVISOR,
                       json={"assigneeId": "OTHER-1", "assignedBy": "someone-else"}).status_code == 403
    assert client.post(f"/v1/review-cases/{case_id}/assignment", headers=SUPERVISOR,
                       json={"assigneeId": "OTHER-1", "assignedBy": "CRMUSER-77"}).status_code == 200
    # comments: stored encrypted, text only for reviewers
    c = client.post(f"/v1/review-cases/{case_id}/comments", headers=REVIEWER,
                    json={"authorId": "CRMUSER-77", "text": "Passport of Testfirst checked"})
    assert c.status_code == 200
    audit = {**REVIEWER, "X-Reviewer-Roles": "AUDIT_REPORTING"}
    assert client.post(f"/v1/review-cases/{case_id}/comments", headers=audit,
                       json={"authorId": "CRMUSER-77", "text": "x"}).status_code == 403
    full = client.get(f"/v1/review-cases/{case_id}", headers=REVIEWER).json()
    assert full["comments"][0]["text"].startswith("Passport") and full["assignedTo"] == "OTHER-1"
    assert "text" not in client.get(f"/v1/review-cases/{case_id}", headers=audit).json()["comments"][0]
    # decision events, then history without personal details
    case, vs = versions(client, case_id)
    prep = prepare(client, case_id, "CONFIRM_DIFFERENT_PEOPLE", vs).json()
    client.post(f"/v1/review-decisions/{prep['reviewDecisionId']}/commit", json={})
    h = client.get(f"/v1/review-cases/{case_id}/history", headers=audit)
    assert h.status_code == 200
    types = [e["type"] for e in h.json()["history"]]
    assert types == ["CREATED", "ASSIGNED", "ASSIGNED", "COMMENTED", "DECISION_PREPARED", "COMMITTED"]
    blob = h.text.lower()
    for pii in ("testfirst", "testlast", "passport", "1985", "555", "gir-synthetic"):
        assert pii not in blob
    assert client.get("/v1/review-cases/RC-NONE/history", headers=REVIEWER).status_code == 404
    # closed cases leave the default queue and cannot be assigned
    assert client.get("/v1/review-cases", headers=REVIEWER).json()["total"] == 0
    assert client.get("/v1/review-cases?status=REVIEW_COMMITTED", headers=REVIEWER).json()["total"] == 1
    assert client.post(f"/v1/review-cases/{case_id}/assignment", headers=REVIEWER,
                       json={"assigneeId": "CRMUSER-77", "assignedBy": "CRMUSER-77"}).status_code == 409


def test_queue_orders_high_priority_first(client):
    four_field_case(client)                                           # NORMAL
    established(client, guest="RQ1", phone="+1 202 555 0141", email="q1@gir-synthetic.invalid")
    established(client, guest="RQ2", phone="+1 202 555 0142", email="q2@gir-synthetic.invalid")
    evaluate(client, event(guest="RQ3", phone="+1 202 555 0141", email="q2@gir-synthetic.invalid"))   # HIGH
    cases = client.get("/v1/review-cases", headers=REVIEWER).json()["cases"]
    assert [c["priority"] for c in cases] == ["HIGH", "NORMAL"]
