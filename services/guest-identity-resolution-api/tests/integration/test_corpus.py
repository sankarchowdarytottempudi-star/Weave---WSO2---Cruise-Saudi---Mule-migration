"""Runs every corpus case end to end against the API and a real PostgreSQL (21.7)."""
import json
import pathlib
import time

import jsonschema
import pytest

from app.services.normalization import normalize_identity
from tests.conftest import TODAY
from tests.integration.conftest import commit, evaluate

D = pathlib.Path(__file__).resolve().parents[1] / "corpus"
SCHEMA = json.loads((D / "corpus-case.schema.json").read_text())
CASES = sorted((D / "cases").glob("*.json"))


@pytest.mark.parametrize("path", CASES, ids=lambda p: p.stem)
def test_corpus_case(path, client, settings_it):
    case = json.loads(path.read_text())
    jsonschema.validate(case, SCHEMA)
    assert case["provenance"] == "SYNTHETIC"
    inp = case["input"]
    n = normalize_identity(inp.get("firstName"), inp.get("lastName"), inp.get("dateOfBirth"), inp.get("phone"),
                           inp.get("email"), inp.get("countryCode"), settings_it, today=TODAY)
    exp = case["expectedNormalization"]
    assert (n.first.canonical, n.last.canonical, n.dob.key.isoformat() if n.dob.key else None, n.phone.e164,
            n.phone.confidence.value, n.email.key) == (exp["firstName"], exp["lastName"], exp["dob"], exp["phoneE164"],
                                                       exp["phoneConfidence"], exp["email"])
    pairs = []
    for e in case["existing"]:
        d = evaluate(client, e["snapshot"])
        pairs.append(commit(client, d) if e.get("commit", True) else d)
    t = time.monotonic()
    d = evaluate(client, inp)
    ms = (time.monotonic() - t) * 1000
    want = case["expected"]
    assert (d["decision"], d["decisionType"], d["reviewRequired"]) == (want["decision"], want["decisionType"], want["reviewRequired"])
    assert set(want["reasonCodesInclude"]) <= set(d["reasonCodes"])
    if want.get("reusesExistingNumber") is not None:
        assert d["globalId"] == pairs[want["reusesExistingNumber"]]["globalId"]
    if want["crmPatch"]:
        assert want["crmPatch"]["identityDecisionType"] == d["decisionType"]
        assert want["crmPatch"]["identityStatus"] == d["identityStatus"]
    final = commit(client, d)["processingState"] if d["processingState"] == "DECIDED_PENDING_CRM" else d["processingState"]
    assert final == want["finalState"]
    assert ms < 2000
