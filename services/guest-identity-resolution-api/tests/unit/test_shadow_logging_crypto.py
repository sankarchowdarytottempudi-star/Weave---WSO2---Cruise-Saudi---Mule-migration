import json
import logging

import pytest

from app.db.crypto import Crypto
from app.observability.logging import JsonFormatter, log, mask, mask_text
from app.services.shadow import jaro_winkler, shadow_score


@pytest.mark.parametrize("a,b,expected", [("martha", "marhta", 0.9611), ("dwayne", "duane", 0.84),
                                          ("dixon", "dicksonx", 0.8133), ("abc", "abc", 1.0), ("", "x", 0.0),
                                          (None, "x", 0.0), ("abc", "xyz", 0.0)])
def test_jaro_winkler_reference_values(a, b, expected):
    assert round(jaro_winkler(a, b), 4) == pytest.approx(expected, abs=1e-3)


def test_shadow_labels():
    assert shadow_score("ali", "ali", "khan", "khan", True, True, True)["label"] == "SHADOW_AUTO_CANDIDATE"
    assert shadow_score("ali", "ali", "khan", "khan", True, False, False)["label"] == "SHADOW_SEPARATE"
    assert shadow_score("ali", "ali", "khan", "khan", True, True, False)["label"] == "SHADOW_REVIEW_CANDIDATE"


def test_mask_hides_pii():
    out = mask({"firstName": "Ali", "nested": {"email": "a@b.com"}, "note": "call +966 55 123 4567 or a@b.com",
                "decisionId": "IDDEC-1", "list": [{"phone": "1"}]})
    assert out["firstName"] == "<masked>" and out["nested"]["email"] == "<masked>"
    assert "<phone>" in out["note"] and "<email>" in out["note"] and out["decisionId"] == "IDDEC-1"
    assert mask_text("x@y.io") == "<email>"


def test_json_formatter_masks(capsys):
    logger = logging.getLogger("t.mask")
    rec = logger.makeRecord("t", logging.INFO, "f", 1, "hello a@b.com", None, None,
                            extra={"fields": {"globalId": "01ABC", "correlationId": "C-1"}})
    data = json.loads(JsonFormatter().format(rec))
    assert data["globalId"] == "<masked>" and data["correlationId"] == "C-1" and "a@b.com" not in data["message"]
    log(logger, "ok", level=logging.DEBUG, x=1)


def test_crypto_roundtrip_and_keys_hidden(settings):
    c = Crypto(settings.data_key_b64, "k1", settings.hmac_key_b64)
    blob = c.encrypt("Muhammad")
    assert b"Muhammad" not in blob and c.decrypt(blob) == "Muhammad"
    assert c.encrypt(None) is None and c.decrypt(None) is None
    assert c.keyed_hash("X") == c.keyed_hash("X") != c.keyed_hash("Y") and c.keyed_hash(None) is None
    assert settings.data_key_b64 not in repr(c) and "data_key_b64" not in repr(settings).split("data_key_id")[0][-5:]
    with pytest.raises(RuntimeError):
        Crypto("", "k1", settings.hmac_key_b64)
    with pytest.raises(RuntimeError):
        Crypto("c2hvcnQ=", "k1", settings.hmac_key_b64)



def test_sla_business_days_skip_the_ksa_weekend(settings):
    from datetime import datetime, timezone
    from app.services.sla import due_time
    thu = datetime(2026, 11, 19, 10, 0, tzinfo=timezone.utc)          # Thursday
    assert due_time(settings, "MULTIPLE_IDENTITY_CONFLICT", thu).date().isoformat() == "2026-11-22"   # Sunday
    assert due_time(settings, "FOUR_FIELD_REVIEW", thu).date().isoformat() == "2026-11-23"
    fri = datetime(2026, 11, 20, 10, 0, tzinfo=timezone.utc)
    assert due_time(settings, "PAIR_REPAIR", fri).date().isoformat() == "2026-11-23"
