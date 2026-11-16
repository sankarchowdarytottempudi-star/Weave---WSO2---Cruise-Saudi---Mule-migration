"""API behaviour: auth, health, scope, re-evaluation, shadow-only, guardrail, suppression, legacy IDs."""
from sqlalchemy import text

from tests.integration.conftest import commit, established, evaluate, event


def test_auth_is_required_and_fails_closed(client, make_client):
    ev = event()
    assert client.post("/v1/guest-identities/evaluate", json=ev, headers={"Authorization": "Bearer wrong"}).status_code == 401
    assert client.post("/v1/guest-identities/evaluate", json=ev, headers={"Authorization": ""}).status_code == 401
    no_token = make_client(service_token="")
    r = no_token.post("/v1/guest-identities/evaluate", json=ev)
    assert r.status_code == 401 and r.json()["code"] == "UNAUTHORIZED"


def test_health_and_metrics(client):
    assert client.get("/health/live").json()["status"] == "UP"
    ready = client.get("/health/ready")
    assert ready.status_code == 200 and ready.json()["schema"] == "0004_review_workbench"
    assert "gir_decisions_total" in client.get("/metrics").text


def test_validation_errors_never_echo_input(client):
    r = client.post("/v1/guest-identities/evaluate", json=event(schemaVersion="9.9", firstName="SecretName"))
    assert r.status_code == 422 and r.json()["code"] == "INVALID_REQUEST" and "SecretName" not in r.text
    wrong = client.post("/v1/guest-identities/evaluate", json=event(kind="GUEST_IDENTITY_REEVALUATION_REQUESTED"))
    assert wrong.status_code == 422


def test_out_of_scope_is_excluded_and_committed_without_crm(client):
    for src, ag in (("INT-AGENT", "AROYA CRUISES MAIN OFFICE"), ("MOBAPP", "SOME TRAVEL AGENCY")):
        d = evaluate(client, event(source=src, agency=ag))
        assert d["decision"] == "EXCLUDED_NON_DIRECT" and not d["crmUpdateRequired"] and d["processingState"] == "COMMITTED"
        assert d["globalId"] is None


def test_excluded_guest_is_never_a_candidate(client):
    evaluate(client, event(guest="RX1", source="INT-AGENT", email="x@gir-synthetic.invalid"))
    d = evaluate(client, event(guest="RX2", email="x@gir-synthetic.invalid"))
    assert d["decision"] == "CREATE_NEW_IDENTITY"


def test_reevaluation_keeps_existing_ids_and_opens_conflict_review(client):
    a = established(client, guest="RR1", phone="+1 202 555 0101", email="r1@gir-synthetic.invalid")
    b = established(client, guest="RR2", first="Otherfirst", phone="+1 202 555 0102", email="r2@gir-synthetic.invalid")
    # harmless correction: no CRM update needed
    same = evaluate(client, event(guest="RR1", t="2026-11-16T11:00:00Z", phone="+1 202 555 0101",
                                  email="r1@gir-synthetic.invalid", kind="GUEST_IDENTITY_REEVALUATION_REQUESTED"),
                    "/v1/guest-identities/re-evaluate")
    assert same["decision"] == "KEEP_EXISTING_IDENTITY" and not same["reviewRequired"] and same["globalId"] == a["globalId"]
    # RR2 edited to become RR1's twin: IDs unchanged, conflict review opened
    d = evaluate(client, event(guest="RR2", t="2026-11-16T11:00:00Z", phone="+1 202 555 0101",
                               email="r1@gir-synthetic.invalid", kind="GUEST_IDENTITY_REEVALUATION_REQUESTED"),
                 "/v1/guest-identities/re-evaluate")
    assert d["decision"] == "KEEP_EXISTING_IDENTITY" and d["reviewRequired"] and d["globalId"] == b["globalId"]
    assert "REEVALUATION_CONFLICT" in d["reasonCodes"]


def test_reevaluation_with_crm_identity_unknown_to_index(client, db):
    d = evaluate(client, event(guest="RZ1", currentIdentityId="CRM-EXT-1", currentGlobalId="01JD8Z6Q5W3F0B4N2K7XGQ1M9T",
                               currentLoyaltyId="1200000050", kind="GUEST_IDENTITY_REEVALUATION_REQUESTED"),
                 "/v1/guest-identities/re-evaluate")
    assert d["decision"] == "KEEP_EXISTING_IDENTITY" and d["globalId"] == "01JD8Z6Q5W3F0B4N2K7XGQ1M9T"
    reuse = evaluate(client, event(guest="RZ2"))
    assert reuse["decision"] == "REUSE_EXISTING_IDENTITY" and reuse["crmIdentityRecordId"] == "CRM-EXT-1"


def test_legacy_global_id_with_dash_is_never_reused(client):
    evaluate(client, event(guest="RL1", currentIdentityId="CRM-LEG", currentGlobalId="8f14e45f-ceea-467f-a8c2-1b2c3d4e5f60",
                           currentLoyaltyId="1200000050"))
    d = evaluate(client, event(guest="RL2"))
    assert d["decisionType"] == "PAIR_REPAIR" and "MATCHED_IDENTITY_NOT_READY" in d["reasonCodes"]


def test_shadow_only_records_but_applies_nothing(make_client, db):
    c = make_client(shadow_only_enabled=True)
    d = evaluate(c, event(guest="RS1"))
    assert d["decision"] == "CREATE_NEW_IDENTITY" and d["globalId"] is None and not d["crmUpdateRequired"]
    assert d["processingState"] == "COMMITTED" and "SHADOW_ONLY_NOT_APPLIED" in d["reasonCodes"]
    with db.connect() as conn:
        assert conn.execute(text("SELECT count(*) FROM identity_projection")).scalar() == 0


def test_guardrail_bounds_candidate_retrieval(make_client):
    c = make_client(candidate_guardrail=2)
    for i in range(4):
        evaluate(c, event(guest=f"RGD{i}", first=f"N{i}x", phone=f"+1 202 555 01{i:02d}", email="shared.gr@gir-synthetic.invalid",
                          dob=f"19{70 + i}-01-02"))
    d = evaluate(c, event(guest="RGD9", email="shared.gr@gir-synthetic.invalid"))
    assert d["decisionType"] == "GUARDRAIL" and d["reviewRequired"]


def test_over_shared_email_is_suppressed(client):
    for i in range(6):
        established(client, guest=f"RO{i}", first=f"P{i}y", phone=None, email="family@gir-synthetic.invalid")
    d = evaluate(client, event(guest="RO9", first="P0y", phone=None, email="family@gir-synthetic.invalid"))
    assert d["decision"] == "CREATE_NEW_IDENTITY"


def test_suspicious_dob_counts_until_over_shared(client):
    established(client, guest="RV1", dob="1970-01-01", email="v@gir-synthetic.invalid")
    d = evaluate(client, event(guest="RV2", dob="1970-01-01", email="v@gir-synthetic.invalid"))
    assert d["decision"] == "REUSE_EXISTING_IDENTITY"


def test_pair_format_is_the_ported_mule_format(client):
    from app.services.pair_allocator import is_valid_loyalty_id
    d = evaluate(client, event())
    assert len(d["globalId"]) == 26 and d["globalId"].isalnum() and is_valid_loyalty_id(d["loyaltyId"])


def test_values_are_encrypted_at_rest(client, db):
    d = evaluate(client, event(guest="RENC", first="Plaintextname", email="enc@gir-synthetic.invalid"))
    with db.connect() as c:
        row = c.execute(text("SELECT source_first_name_enc, source_email_enc FROM guest_match_index "
                             "WHERE crm_guest_record_id='RENC'")).one()
        ids = c.execute(text("SELECT global_id_enc, global_id_hash FROM identity_projection")).one()
    assert b"Plaintextname" not in bytes(row[0]) and b"enc@example" not in bytes(row[1])
    assert d["globalId"].encode() not in bytes(ids[0]) and d["globalId"] not in ids[1]


def test_sequence_allocator_strategy(make_client):
    c = make_client(id_allocation_strategy="SEQUENCE")
    d = evaluate(c, event())
    assert d["globalId"].startswith("G") and d["loyaltyId"].startswith("L")


def test_mobile_and_phone_fields_both_match(client):
    a = established(client, guest="RM1", phone=None, alternatePhone="+1 202 555 0188", email="")
    d = evaluate(client, event(guest="RM2", phone="+1 202 555 0188", email=""))
    assert d["decision"] == "REUSE_EXISTING_IDENTITY" and d["globalId"] == a["globalId"]


def test_loyalty_under_two_global_ids_makes_both_conflict(client, db):
    batch = {"batchId": "lc-1", "records": [
        {"crmGuestRecordId": "LC1", "crmModifiedTime": "2026-11-01T00:00:00Z", "firstName": "Lcfirst", "lastName": "Lclast",
         "currentGlobalId": "01JD8Z6Q5W3F0B4N2K7XGQDDDD", "currentLoyaltyId": "1200000048"},
        {"crmGuestRecordId": "LC2", "crmModifiedTime": "2026-11-01T00:00:00Z", "firstName": "Lcfirst", "lastName": "Lclast",
         "currentGlobalId": "01JD8Z6Q5W3F0B4N2K7XGQEEEE", "currentLoyaltyId": "1200000048"}]}
    assert client.post("/v1/bootstrap/batches", json=batch).status_code == 200
    with db.connect() as c:
        assert {r[0] for r in c.execute(text("SELECT pair_integrity FROM identity_projection"))} == {"CONFLICT"}


def test_rate_limit_returns_429_and_exempts_health(make_client):
    c = make_client(rate_limit_per_minute=3)
    codes = [c.get("/v1/guest-identities/decisions/IDDEC-X").status_code for _ in range(5)]
    assert codes[:3] == [404, 404, 404] and codes[3:] == [429, 429]
    assert c.get("/health/live").status_code == 200
