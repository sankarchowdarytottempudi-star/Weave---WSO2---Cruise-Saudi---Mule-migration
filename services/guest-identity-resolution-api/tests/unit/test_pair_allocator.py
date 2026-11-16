"""Global/Loyalty generation ported from Mule identity-support-exp-api."""
import re

import pytest

from app.services.pair_allocator import (MuleCompatPairAllocator, PairAllocationError, SequencePairAllocator,
                                         aroya_check_digit, build_allocator, is_reusable_pair,
                                         is_valid_loyalty_id, loyalty_id, ulid)

ULID_RE = re.compile(r"^[0-9A-HJKMNP-TV-Z]{26}$")


def textbook_luhn_check(base: str) -> str:
    total = 0
    for i, d in enumerate(int(c) for c in reversed(base)):
        if i % 2 == 0:
            d *= 2
            d = d - 9 if d > 9 else d
        total += d
    return str((10 - total % 10) % 10)


def test_ulid_format_and_time_order():
    a, b = ulid(now_ms=1_700_000_000_000, randomness=0), ulid(now_ms=1_700_000_000_001, randomness=0)
    assert ULID_RE.match(a) and len(a) == 26 and a < b
    assert ulid(now_ms=0, randomness=0) == "0" * 26
    assert ULID_RE.match(ulid())


@pytest.mark.parametrize("base,check", [("120000001", "4"), ("120000005", "0"), ("123456789", None)])
def test_check_digit_is_the_mule_dataweave_function(base, check):
    # reproduced by hand from the DataWeave: reversed digits, ODD indexes doubled
    digits = [int(c) for c in reversed(base)]
    total = sum((d * 2 - 9 if d * 2 > 9 else d * 2) if i % 2 == 1 else d for i, d in enumerate(digits))
    expected = str((10 - total % 10) % 10)
    assert aroya_check_digit(base) == expected
    if check:
        assert expected == check


def test_mule_check_digit_differs_from_textbook_luhn_and_is_kept():
    assert aroya_check_digit("120000005") == "0" and textbook_luhn_check("120000005") == "5"


def test_loyalty_id_shape():
    v = loyalty_id(rand=lambda n: 5)
    assert v == "1200000050" and is_valid_loyalty_id(v)
    for _ in range(200):
        x = loyalty_id()
        assert len(x) == 10 and x.startswith("12") and x.isdigit() and is_valid_loyalty_id(x)
    assert not is_valid_loyalty_id("1200000051") and not is_valid_loyalty_id("130000005X")


def test_mule_eligibility_rule():
    assert is_reusable_pair("01JD8Z6Q5W3F0B4N2K7XGQ1M9T", "1200000050")
    assert not is_reusable_pair("8f14e45f-ceea-467f-a8c2-1b2c3d4e5f60", "1200000050")   # legacy '-' form
    assert not is_reusable_pair(None, "1200000050") and not is_reusable_pair("01JD", None)


class _FakeConn:
    def __init__(self, taken_hashes):
        self.taken = taken_hashes


def test_allocator_redraws_on_collision_and_gives_up(settings, monkeypatch):
    from app.db.crypto import Crypto
    crypto = Crypto(settings.data_key_b64, "k1", settings.hmac_key_b64)
    seq = iter(["1200000050", "1200000050", "1200000014"])
    alloc = MuleCompatPairAllocator(settings, crypto, global_gen=lambda: "G", loyalty_gen=lambda: next(seq))
    taken = {crypto.keyed_hash("1200000050")}
    monkeypatch.setattr(alloc, "_taken", lambda conn, g, l: crypto.keyed_hash(l) in taken)
    assert alloc.allocate(None) == ("G", "1200000014")
    always = MuleCompatPairAllocator(settings, crypto, global_gen=lambda: "G", loyalty_gen=lambda: "1200000050")
    monkeypatch.setattr(always, "_taken", lambda conn, g, l: True)
    with pytest.raises(PairAllocationError):
        always.allocate(None)


def test_build_allocator_strategy(settings):
    import dataclasses
    from app.db.crypto import Crypto
    crypto = Crypto(settings.data_key_b64, "k1", settings.hmac_key_b64)
    assert isinstance(build_allocator(settings, crypto), MuleCompatPairAllocator)
    assert isinstance(build_allocator(dataclasses.replace(settings, id_allocation_strategy="SEQUENCE"), crypto),
                      SequencePairAllocator)
