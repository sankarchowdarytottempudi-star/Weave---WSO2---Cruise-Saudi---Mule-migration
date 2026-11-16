"""Bootstrap (plan 16), docs protection, and the migrated schema itself."""
import base64
import json

import pytest
from alembic import command
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from tests.conftest import SERVICE_TOKEN
from tests.integration.conftest import SCHEMA, URL, alembic_cfg, evaluate, event


def rec(gid, **kw):
    r = dict(crmGuestRecordId=gid, crmModifiedTime="2026-11-01T00:00:00Z", firstName="Bootfirst", lastName="Bootlast",
             dateOfBirth="1980-02-03", phone="+1 202 555 0100", email=f"{gid.lower()}@gir-synthetic.invalid",
             sourceCode="MOBAPP", agencyName="AROYA CRUISES MAIN OFFICE")
    r.update(kw)
    return r


def test_bootstrap_batch_counts_idempotency_and_reusable_pairs(client):
    batch = {"batchId": "b-001", "records": [
        rec("B1", currentGlobalId="01JD8Z6Q5W3F0B4N2K7XGQ1M9T", currentLoyaltyId="1200000050", email="b@gir-synthetic.invalid"),
        rec("B2", currentGlobalId="01JD8Z6Q5W3F0B4N2K7XGQ1M9T", currentLoyaltyId="1200000050", firstName="Other"),
        rec("B3", currentGlobalId="01JD8Z6Q5W3F0B4N2K7XGQAAAA", email="incomplete@gir-synthetic.invalid"),
        rec("B4", currentGlobalId="01JD8Z6Q5W3F0B4N2K7XGQBBBB", currentLoyaltyId="1200000014"),
        rec("B5", currentGlobalId="01JD8Z6Q5W3F0B4N2K7XGQBBBB", currentLoyaltyId="1200000022"),   # 1:1 broken
        rec("B6", sourceCode="INT-AGENT"),
        rec("B7"),
    ]}
    r = client.post("/v1/bootstrap/batches", json=batch)
    assert r.status_code == 200, r.text
    out = r.json()
    assert out["received"] == 7 and out["indexed"] == 7 and out["linkedToIdentity"] == 5
    assert out["excludedNonDirect"] == 1 and out["pendingIdentity"] == 2 and not out["replayed"]
    assert client.post("/v1/bootstrap/batches", json=batch).json()["replayed"]
    changed = dict(batch, records=batch["records"][:2])
    assert client.post("/v1/bootstrap/batches", json=changed).status_code == 409
    st = client.get("/v1/bootstrap/status").json()
    assert st["identities"]["byPairIntegrity"] == {"COMPLETE": 1, "INCOMPLETE": 1, "CONFLICT": 1}
    # the complete pair is reusable at runtime; the conflicting one is not
    d = evaluate(client, event(guest="BX1", first="Bootfirst", last="Bootlast", dob="1980-02-03",
                               phone=None, email="b@gir-synthetic.invalid"))
    assert d["decision"] == "REUSE_EXISTING_IDENTITY" and d["globalId"] == "01JD8Z6Q5W3F0B4N2K7XGQ1M9T"
    d2 = evaluate(client, event(guest="BX2", first="Bootfirst", last="Bootlast", dob="1980-02-03", phone=None,
                                email="b4@gir-synthetic.invalid"))
    assert d2["decisionType"] == "PAIR_REPAIR"


def test_bootstrap_ndjson_stale_and_validation(client):
    body = "\n".join(json.dumps(rec(f"N{i}")) for i in range(3))
    r = client.post("/v1/bootstrap/batches?batchId=nd-1", content=body,
                    headers={"Content-Type": "application/x-ndjson"})
    assert r.status_code == 200 and r.json()["indexed"] == 3
    old = client.post("/v1/bootstrap/batches", json={"batchId": "nd-2", "records": [rec("N0", crmModifiedTime="2020-01-01T00:00:00Z")]})
    assert old.json()["staleSkipped"] == 1
    assert client.post("/v1/bootstrap/batches", json={"batchId": "x", "records": []}).status_code == 422
    assert client.post("/v1/bootstrap/batches?batchId=", content=body,
                       headers={"Content-Type": "application/x-ndjson"}).status_code == 422
    assert client.post("/v1/bootstrap/batches", content=b"not json").status_code == 422


def test_bootstrap_dry_run_counts_without_writing(client, db):
    recs = [rec("D1", currentGlobalId="01JD8Z6Q5W3F0B4N2K7XGQCCCC", currentLoyaltyId="1200000030", email="d@gir-synthetic.invalid"),
            rec("D2", email="d@gir-synthetic.invalid"), rec("D3", firstName="Zed", phone=None, email="z@gir-synthetic.invalid")]
    client.post("/v1/bootstrap/batches", json={"batchId": "dr-1", "records": recs})
    with db.connect() as c:
        before = c.execute(text("SELECT count(*) FROM identity_projection")).scalar()
    page = client.post("/v1/bootstrap/dry-run", json={"limit": 2}).json()
    assert page["evaluated"] == 2 and page["nextAfterGuestId"] == "D2" and page["dryRun"]
    rest = client.post("/v1/bootstrap/dry-run", json={"limit": 2, "afterGuestId": "D2", "onlyWithoutIdentity": True}).json()
    assert rest["evaluated"] == 1 and rest["nextAfterGuestId"] is None
    assert "CERTAIN_EMAIL" in page["outcomes"] or "CERTAIN_PHONE" in page["outcomes"]
    with db.connect() as c:
        assert c.execute(text("SELECT count(*) FROM identity_projection")).scalar() == before


def test_docs_disabled_by_default_and_protected_when_enabled(client, make_client):
    assert client.get("/docs").status_code == 404 and client.get("/openapi.json").status_code == 404
    c = make_client(docs_enabled=True)
    anon = c.get("/docs", headers={"Authorization": ""})
    assert anon.status_code == 401 and anon.headers["www-authenticate"].startswith("Basic")
    basic = "Basic " + base64.b64encode(f"owner:{SERVICE_TOKEN}".encode()).decode()
    assert c.get("/docs", headers={"Authorization": basic}).status_code == 200
    assert c.get("/openapi.json", headers={"Authorization": basic}).json()["paths"]
    assert c.get("/docs", headers={"Authorization": "Basic " + base64.b64encode(b"o:wrong").decode()}).status_code == 401


def test_schema_constraints_and_indexes(db):
    with db.connect() as c:
        idx = {r[0] for r in c.execute(text("SELECT indexname FROM pg_indexes WHERE schemaname=:s"), {"s": SCHEMA})}
        assert {"gmi_names_dob", "gmi_phone", "gmi_phone_tail", "gmi_email", "gmi_identity", "gmi_dob",
                "gmi_pending", "rcp_queue", "gmi_alt_phone", "gmi_alt_phone_tail"} <= idx
        tables = {r[0] for r in c.execute(text("SELECT tablename FROM pg_tables WHERE schemaname=:s"), {"s": SCHEMA})}
        assert {"guest_match_index", "identity_projection", "processing_request", "identity_decision",
                "identifier_statistics", "review_case_projection", "review_candidate", "review_decision",
                "rule_version", "reconciliation_state", "bootstrap_batch"} <= tables
    with pytest.raises(IntegrityError):
        with db.begin() as c:
            c.execute(text("INSERT INTO identity_projection (identity_id, pair_integrity, lifecycle_status, "
                           "created_by_process, rule_version, created_time, modified_time) VALUES "
                           "(gen_random_uuid(), 'COMPLETE', 'NOT_A_STATE', 'NEW', '1', now(), now())"))
    with pytest.raises(IntegrityError):     # COMPLETE requires both ID hashes
        with db.begin() as c:
            c.execute(text("INSERT INTO identity_projection (identity_id, pair_integrity, lifecycle_status, "
                           "created_by_process, rule_version, created_time, modified_time) VALUES "
                           "(gen_random_uuid(), 'COMPLETE', 'ACTIVE', 'NEW', '1', now(), now())"))


def test_migration_downgrade_upgrade_and_app_role_grants(db):
    with db.begin() as c:
        c.execute(text("DO $$BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='gir_app_it') "
                       "THEN CREATE ROLE gir_app_it NOLOGIN; END IF; END$$"))
    cfg = alembic_cfg(app_role="gir_app_it")
    command.downgrade(cfg, "base")
    command.upgrade(cfg, "head")
    with db.connect() as c:
        privs = {r[0] for r in c.execute(text(
            "SELECT privilege_type FROM information_schema.role_table_grants WHERE grantee='gir_app_it' "
            "AND table_schema=:s AND table_name='guest_match_index'"), {"s": SCHEMA})}
        assert privs == {"SELECT", "INSERT", "UPDATE", "DELETE"}
        assert c.execute(text("SELECT version_num FROM alembic_version")).scalar() == "0004_review_workbench"
