"""Iteration 0 contracts stay consistent with the code."""
import json
import pathlib
import re
import subprocess
import sys

import jsonschema
import pytest
import yaml
from openapi_spec_validator import validate
from openapi_spec_validator.readers import read_from_filename

from app.domain import enums
from app.domain.reason_codes import Reason
from app.schemas.events import DecisionResponse, GuestIdentityEvent
from app.schemas.review import DecisionPreparationRequest

ROOT = pathlib.Path(__file__).resolve().parents[2]
OPENAPI = ROOT / "contracts" / "openapi.yaml"
EVENTS = ROOT / "contracts" / "events"
CATALOGUES = yaml.safe_load((ROOT / "contracts" / "catalogues.yaml").read_text())
SECTION_9_2 = {("post", "/v1/guest-identities/evaluate"), ("post", "/v1/guest-identities/re-evaluate"),
               ("post", "/v1/guest-identities/decisions/{id}/commit"), ("post", "/v1/guest-identities/decisions/{id}/fail"),
               ("get", "/v1/guest-identities/decisions/{id}"), ("get", "/v1/review-cases/{caseId}"),
               ("post", "/v1/review-cases/{caseId}/decision-preparations"),
               ("post", "/v1/review-decisions/{id}/freshness-failed"), ("post", "/v1/review-decisions/{id}/commit"),
               ("post", "/v1/review-decisions/{id}/fail"), ("get", "/health/live"), ("get", "/health/ready")}


@pytest.fixture(scope="module")
def spec():
    d, base = read_from_filename(str(OPENAPI))
    return d, base


def test_openapi_is_valid_3_1(spec):
    d, base = spec
    assert d["openapi"].startswith("3.1")
    validate(d, base_uri=base)


def test_openapi_covers_every_section_9_2_operation(spec):
    ops = {(m, p) for p, item in spec[0]["paths"].items() for m in item}
    assert SECTION_9_2 <= ops


def test_app_routes_match_openapi(spec, settings):
    from sqlalchemy import create_engine
    from app.main import create_app
    app = create_app(settings, create_engine("sqlite://"))
    norm = lambda p: re.sub(r"\{[^}]+\}", "{}", p)
    routes = {(m.lower(), norm(r.path)) for r in app.routes if hasattr(r, "methods") for m in r.methods
              if m != "HEAD" and not r.path.startswith(("/openapi", "/metrics", "/docs"))}
    documented = {(m, norm(p)) for p, item in spec[0]["paths"].items() for m in item}
    assert {(m, norm(p)) for m, p in SECTION_9_2} <= routes
    assert routes == documented


def _schema(name):
    return json.loads((EVENTS / name).read_text())


def test_event_schemas_are_current():
    subprocess.run([sys.executable, str(ROOT / "tools" / "gen_event_schemas.py"), "--check"], check=True)


@pytest.mark.parametrize("name", [p.name for p in EVENTS.glob("*.json")])
def test_event_schemas_are_valid_draft_2020_12(name):
    jsonschema.Draft202012Validator.check_schema(_schema(name))


def test_section_11_examples_validate(spec):
    ex = spec[0]["components"]["examples"]
    ev = ex["EvaluationEvent"]["value"]
    jsonschema.validate(ev, _schema("guest-identity-evaluation-requested.v1.schema.json"))
    GuestIdentityEvent(**ev)
    re_ev = ex["ReevaluationEvent"]["value"]
    jsonschema.validate(re_ev, _schema("guest-identity-reevaluation-requested.v1.schema.json"))
    GuestIdentityEvent(**re_ev)
    d = ex["DecisionResponse"]["value"]
    DecisionResponse(**{**d, "identityStatus": d["identityStatus"], "reasonSummary": ""})
    DecisionPreparationRequest(**ex["DecisionPreparationRequest"]["value"])


def test_event_schema_rejects_missing_identity_and_bad_version():
    s = _schema("guest-identity-evaluation-requested.v1.schema.json")
    good = dict(schemaVersion="1.0", eventId="E", eventType="GUEST_IDENTITY_EVALUATION_REQUESTED", correlationId="C",
                sourceSystem="S", sourceRecordId="1", crmGuestRecordId="R", crmModifiedTime="2026-11-16T10:00:00Z",
                email="x@gir-synthetic.invalid")
    jsonschema.validate(good, s)
    for bad in ({**good, "schemaVersion": "2.0"}, {k: v for k, v in good.items() if k != "email"}, {**good, "x": 1}):
        with pytest.raises(jsonschema.ValidationError):
            jsonschema.validate(bad, s)


def test_dlq_schema_has_no_identity_values():
    props = set(_schema("guest-identity-processing-dlq.v1.schema.json")["properties"])
    assert not props & {"firstName", "lastName", "dateOfBirth", "phone", "email", "payload"}


@pytest.mark.parametrize("key,enum", [("identity_statuses", enums.IdentityStatus), ("decisions", enums.Decision),
                                      ("decision_types", enums.DecisionType), ("processing_states", enums.ProcessingState),
                                      ("review_states", enums.ReviewState), ("reviewer_actions", enums.ReviewerAction),
                                      ("review_kinds", enums.ReviewKind), ("reason_codes", Reason)])
def test_catalogues_match_enums(key, enum):
    assert set(CATALOGUES[key]) == {e.value for e in enum}


def test_catalogues_match_db_checks_and_state_machine():
    from app.domain import state_machine
    mig = (ROOT / "migrations" / "versions" / "0001_initial.py").read_text()
    for v in CATALOGUES["processing_states"]:
        assert f"'{v}'" in mig
    for v in CATALOGUES["review_states"]:
        assert f"'{v}'" in mig
    for v in CATALOGUES["reviewer_actions"]:
        assert f"'{v}'" in mig
    for src, targets in CATALOGUES["processing_transitions"].items():
        assert {t.value for t in state_machine.PROCESSING[enums.ProcessingState(src)]} == set(targets)
    for src, targets in CATALOGUES["review_transitions"].items():
        assert {t.value for t in state_machine.REVIEW[enums.ReviewState(src)]} == set(targets)


def test_config_catalogue_envs_exist_in_code():
    cat = (ROOT / "config" / "config-catalogue.yaml").read_text()
    code = (ROOT / "app" / "config.py").read_text()
    for env in set(re.findall(r"env: (GIR_[A-Z_]+)", cat)):
        name = env[:-5] if env.endswith("_FILE") else env
        assert f'"{name}"' in code, env
    yaml.safe_load(cat)


def test_crm_spec_picklists_match_catalogues():
    crm = yaml.safe_load((ROOT / "contracts" / "crm" / "zoho-crm-configuration-spec.yaml").read_text())
    contacts = crm["modules"]["Contacts"]["new_fields"]
    assert set(contacts["Identity_Status"]["values"]) == set(CATALOGUES["identity_statuses"])
    assert set(contacts["Identity_Decision_Type"]["values"]) == set(CATALOGUES["decision_types"])
    cases = crm["modules"]["Identity_Review_Cases"]["fields"]
    assert set(cases["Case_Status"]["values"]) == set(CATALOGUES["review_states"])
    assert set(cases["Last_Action"]["values"]) == set(CATALOGUES["reviewer_actions"])
