"""Plan 21.4 cases that need the database (11-13) plus end-to-end versions of the rule cases."""
import threading

from sqlalchemy import text

from tests.integration.conftest import commit, established, evaluate, event


def test_21_4_01_e2e_certain_phone_reuse(client):
    first = established(client, guest="RA1", email="")
    d = evaluate(client, event(guest="RA2", email=""))
    assert d["decision"] == "REUSE_EXISTING_IDENTITY" and d["decisionType"] == "CERTAIN_PHONE"
    assert (d["globalId"], d["loyaltyId"]) == (first["globalId"], first["loyaltyId"])
    assert commit(client, d)["processingState"] == "COMMITTED"


def test_21_4_02_e2e_certain_email_reuse(client):
    established(client, guest="RB1", phone=None, email="same.person@gir-synthetic.invalid")
    d = evaluate(client, event(guest="RB2", phone=None, email="same.person@gir-synthetic.invalid"))
    assert d["decisionType"] == "CERTAIN_EMAIL"


def test_21_4_03_e2e_four_field_review(client):
    established(client, guest="RC1", email="ff@gir-synthetic.invalid")
    d = evaluate(client, event(guest="RC2", dob="1986-05-10", email="ff@gir-synthetic.invalid"))
    assert d["decisionType"] == "FOUR_FIELD" and d["reviewRequired"] and d["provisional"] and d["reviewCaseId"]
    assert d["globalId"] and d["loyaltyId"]


def test_21_4_09_e2e_multiple_identities(client):
    established(client, guest="RD1", phone="+1 202 555 0111", email="m1@gir-synthetic.invalid")
    established(client, guest="RD2", phone="+1 202 555 0122", email="m2@gir-synthetic.invalid")
    d = evaluate(client, event(guest="RD3", phone="+1 202 555 0111", email="m2@gir-synthetic.invalid"))
    assert d["decisionType"] == "MULTIPLE_IDENTITY" and d["reviewPriority"] == "HIGH"


def test_21_4_11_duplicate_event_and_timeout_retry_return_same_decision_and_pair(client):
    ev = event(guest="RE1")
    a = evaluate(client, ev)
    retry = dict(ev, eventId="another-delivery", correlationId="CORR-retry")
    b = evaluate(client, retry)
    assert a["decisionId"] == b["decisionId"] and (a["globalId"], a["loyaltyId"]) == (b["globalId"], b["loyaltyId"])
    conflict = client.post("/v1/guest-identities/evaluate", json=dict(ev, firstName="Different"))
    assert conflict.status_code == 409 and conflict.json()["code"] == "IDEMPOTENCY_CONFLICT"


def test_21_4_12_older_crm_event_cannot_overwrite_newer_values(client, db):
    evaluate(client, event(guest="RF1", t="2026-11-16T12:00:00Z", first="Newer"))
    old = client.post("/v1/guest-identities/evaluate", json=event(guest="RF1", t="2026-11-16T11:00:00Z", first="Older"))
    assert old.status_code == 409 and old.json()["code"] == "STALE_CRM_EVENT"
    with db.connect() as c:
        assert c.execute(text("SELECT canonical_first_name FROM guest_match_index WHERE crm_guest_record_id='RF1'")).scalar() == "newer"
        assert c.execute(text("SELECT state FROM processing_request WHERE state='REJECTED_STALE'")).scalar() == "REJECTED_STALE"
    again = client.post("/v1/guest-identities/evaluate", json=event(guest="RF1", t="2026-11-16T11:00:00Z", first="Older"))
    assert again.status_code == 409


def test_21_4_13_crm_failure_retries_without_exposing_uncommitted_pair(client):
    a = evaluate(client, event(guest="RG1", email="g@gir-synthetic.invalid"))
    f = client.post(f"/v1/guest-identities/decisions/{a['decisionId']}/fail",
                    json={"retryable": True, "errorCode": "CRM_TIMEOUT"}).json()
    assert f["processingState"] == "CRM_UPDATE_FAILED" and f["globalId"] == a["globalId"]
    # the same person arrives while the pair is uncommitted: never reused
    b = evaluate(client, event(guest="RG2", email="g@gir-synthetic.invalid"))
    assert b["decision"] == "CREATE_PROVISIONAL_IDENTITY" and b["decisionType"] == "PAIR_REPAIR"
    assert b["globalId"] != a["globalId"]
    # retry succeeds with the SAME pair
    c = commit(client, f)
    assert c["processingState"] == "COMMITTED" and c["globalId"] == a["globalId"]
    # a third arrival now sees two distinct identities (RG1 committed, RG2's provisional) -> conflict review
    d = evaluate(client, event(guest="RG3", email="g@gir-synthetic.invalid"))
    assert d["decisionType"] == "MULTIPLE_IDENTITY" and d["globalId"] not in (a["globalId"], b["globalId"])


def test_committed_pair_becomes_reusable_only_after_commit(client):
    a = evaluate(client, event(guest="RQ1", email="q@gir-synthetic.invalid"))
    commit(client, a)
    d = evaluate(client, event(guest="RQ2", email="q@gir-synthetic.invalid"))
    assert d["decision"] == "REUSE_EXISTING_IDENTITY" and d["globalId"] == a["globalId"]


def test_terminal_failure_and_invalid_transitions(client):
    a = evaluate(client, event(guest="RH1"))
    f = client.post(f"/v1/guest-identities/decisions/{a['decisionId']}/fail", json={"retryable": False, "errorCode": "X"})
    assert f.json()["processingState"] == "FAILED"
    bad = client.post(f"/v1/guest-identities/decisions/{a['decisionId']}/commit", json={"crmIdentityRecordId": "C"})
    assert bad.status_code == 409 and bad.json()["code"] == "INVALID_STATE"


def test_commit_requires_crm_identity_id_and_is_idempotent(client):
    a = evaluate(client, event(guest="RI1"))
    r = client.post(f"/v1/guest-identities/decisions/{a['decisionId']}/commit", json={})
    assert r.status_code == 422
    c1 = commit(client, a, "CRM-I1")
    c2 = client.post(f"/v1/guest-identities/decisions/{a['decisionId']}/commit", json={"crmIdentityRecordId": "CRM-I1"})
    assert c2.status_code == 200 and c2.json()["crmIdentityRecordId"] == c1["crmIdentityRecordId"] == "CRM-I1"
    assert client.get(f"/v1/guest-identities/decisions/{a['decisionId']}").json()["processingState"] == "COMMITTED"
    assert client.get("/v1/guest-identities/decisions/IDDEC-NOPE").status_code == 404


def test_concurrent_duplicate_deliveries_create_one_decision_and_one_pair(client, db):
    ev = event(guest="RJ1")
    out, errors = [], []

    def go():
        r = client.post("/v1/guest-identities/evaluate", json=ev)
        (out if r.status_code == 200 else errors).append(r)
    threads = [threading.Thread(target=go) for _ in range(8)]
    [t.start() for t in threads]
    [t.join() for t in threads]
    assert not errors and len({r.json()["decisionId"] for r in out}) == 1
    with db.connect() as c:
        assert c.execute(text("SELECT count(*) FROM identity_projection")).scalar() == 1


def test_concurrent_same_person_never_gets_two_permanent_pairs(client, db):
    evs = [event(guest=f"RK{i}", email="same@gir-synthetic.invalid") for i in range(3)]
    res = []
    threads = [threading.Thread(target=lambda e=e: res.append(client.post("/v1/guest-identities/evaluate", json=e)))
               for e in evs]
    [t.start() for t in threads]
    [t.join() for t in threads]
    decisions = [r.json() for r in res]
    assert all(r.status_code == 200 for r in res)
    assert sum(1 for d in decisions if d["decision"] == "CREATE_NEW_IDENTITY") == 1
    assert all(d["decisionType"] in ("NEW", "PAIR_REPAIR", "MULTIPLE_IDENTITY") for d in decisions)
