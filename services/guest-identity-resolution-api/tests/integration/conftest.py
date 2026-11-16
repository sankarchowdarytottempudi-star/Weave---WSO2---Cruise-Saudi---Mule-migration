"""Integration fixtures: a REAL throwaway PostgreSQL 16 (GIR_TEST_DATABASE_URL), migrated with
Alembic into a dedicated schema, truncated between tests. Synthetic data only."""
from __future__ import annotations

import os
import pathlib
import uuid

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import text

from app.db.session import make_engine
from app.main import create_app
from tests.conftest import SERVICE_TOKEN, make_settings

ROOT = pathlib.Path(__file__).resolve().parents[2]
URL = os.environ.get("GIR_TEST_DATABASE_URL")
SCHEMA = "gir_it"
TABLES = ("review_decision", "review_candidate", "review_case_projection", "identity_decision", "processing_request",
          "identifier_statistics", "guest_match_index", "identity_projection", "rule_version", "reconciliation_state",
          "bootstrap_batch")

pytestmark = pytest.mark.integration


def alembic_cfg(url=URL, schema=SCHEMA, app_role=""):
    cfg = Config(str(ROOT / "alembic.ini"))
    cfg.set_main_option("script_location", str(ROOT / "migrations"))
    cfg.attributes.update(url=url, schema=schema, app_role=app_role)
    return cfg


@pytest.fixture(scope="session")
def engine():
    if not URL:
        pytest.skip("GIR_TEST_DATABASE_URL not set")
    eng = make_engine(URL, SCHEMA)
    with eng.begin() as c:
        c.execute(text(f'DROP SCHEMA IF EXISTS "{SCHEMA}" CASCADE'))
    command.upgrade(alembic_cfg(), "head")
    yield eng
    eng.dispose()


@pytest.fixture
def db(engine):
    with engine.begin() as c:
        c.execute(text("TRUNCATE " + ", ".join(TABLES) + " RESTART IDENTITY CASCADE"))
    return engine


@pytest.fixture
def settings_it():
    return make_settings(database_url=URL, database_schema=SCHEMA)


@pytest.fixture
def make_client(db):
    def _make(**over):
        s = make_settings(database_url=URL, database_schema=SCHEMA, **over)
        app = create_app(s, db)
        return TestClient(app, raise_server_exceptions=bool(os.environ.get("GIR_RAISE")), headers={"Authorization": f"Bearer {SERVICE_TOKEN}"})
    return _make


@pytest.fixture
def client(make_client):
    return make_client()


_seq = iter(range(1, 10**9))


def event(guest=None, first="Testfirst", last="Testlast", dob="1985-05-10", phone="+1 202 555 0123",
          email=None, t="2026-11-16T10:00:00Z", source="MOBAPP", agency="AROYA CRUISES MAIN OFFICE",
          kind="GUEST_IDENTITY_EVALUATION_REQUESTED", **extra):
    guest = guest or f"R{next(_seq)}"
    ev = dict(schemaVersion="1.0", eventId=str(uuid.uuid4()), eventType=kind, correlationId="CORR-" + guest,
              sourceSystem="SEAWARE", sourceRecordId="S-" + guest, crmGuestRecordId=guest, crmModifiedTime=t,
              firstName=first, lastName=last, dateOfBirth=dob, phone=phone,
              email=email if email is not None else f"{guest.lower()}@gir-synthetic.invalid",
              sourceCode=source, agencyName=agency)
    ev.update(extra)
    return ev


def evaluate(client, ev, path="/v1/guest-identities/evaluate"):
    r = client.post(path, json=ev)
    assert r.status_code == 200, r.text
    return r.json()


def commit(client, d, crm_id=None):
    body = {"crmIdentityRecordId": crm_id or ("CRMID-" + d["decisionId"])} if d["globalId"] and d["processingState"] \
        in ("DECIDED_PENDING_CRM", "CRM_UPDATE_FAILED") else {}
    r = client.post(f"/v1/guest-identities/decisions/{d['decisionId']}/commit", json=body)
    assert r.status_code == 200, r.text
    return r.json()


def established(client, **kw):
    """A committed identity with one Guest - the base for CERTAIN tests."""
    d = evaluate(client, event(**kw))
    assert d["decision"] == "CREATE_NEW_IDENTITY"
    return commit(client, d)
