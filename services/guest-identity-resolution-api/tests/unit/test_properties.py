"""Hypothesis property tests: blanks never agree, shadow never changes production, order independence."""
import dataclasses
import random
from datetime import date

from hypothesis import HealthCheck, given, settings as hsettings, strategies as st

from app.domain.enums import FieldResult, PairIntegrity
from app.services.rule_engine import Candidate, decide, evaluate_candidate
from tests.conftest import make_settings, norm

S = make_settings()
DIRECT = dict(source_code="MOBAPP", agency_code="AROYA CRUISES MAIN OFFICE", source_system="SEAWARE")
blankish = st.sampled_from([None, "", "   ", "\t"])
names = st.sampled_from(["muhammad", "mohammed", "ali", "sara", "fatima", None])
dobs = st.sampled_from([date(1985, 5, 10), date(1990, 1, 1), None])
phones = st.sampled_from(["+966551234567", "+966501112222", None])
emails = st.sampled_from(["a@gir-synthetic.invalid", "b@gir-synthetic.invalid", None])
idents = st.sampled_from(["I-1", "I-2", "I-3", None])


@st.composite
def candidates(draw):
    ident = draw(idents)
    ph = draw(phones)
    return Candidate(f"R{draw(st.integers(1, 10**6))}", ident, draw(names), draw(names), draw(dobs), ph,
                     ph[-9:] if ph else None, draw(emails),
                     draw(st.sampled_from(list(PairIntegrity))) if ident else None,
                     draw(st.booleans()) if ident else False)


@given(first=blankish, last=blankish, dob=blankish, phone=blankish, email=blankish, c=candidates())
@hsettings(max_examples=150, suppress_health_check=[HealthCheck.too_slow])
def test_blank_never_agrees(first, last, dob, phone, email, c):
    n = norm(S, first, last, dob, phone, email)
    blank_c = dataclasses.replace(c, first=None, last=None, dob=None, phone_e164=None, phone_tail=None, email=None)
    for cc in (c, blank_c):
        e = evaluate_candidate(n, cc, set(), set())
        assert e.exact_count == 0 and not e.certain
        assert all(v != FieldResult.EXACT.value for v in e.fields.values())


@given(cs=st.lists(candidates(), max_size=8), first=names, dob=st.sampled_from(["1985-05-10", None]),
       phone=st.sampled_from(["+966 55 123 4567", None]), email=emails)
@hsettings(max_examples=150, suppress_health_check=[HealthCheck.too_slow])
def test_shadow_never_changes_production(cs, first, dob, phone, email):
    n = norm(S, first, "ali", dob, phone, email)
    on = decide(n, cs, settings=S, **DIRECT)
    off = decide(n, cs, settings=dataclasses.replace(S, weighted_shadow_enabled=False), **DIRECT)
    assert (on.decision, on.decision_type, on.identity_status, on.reuse_identity_id, on.review_required,
            [str(r) for r in on.reasons]) == \
           (off.decision, off.decision_type, off.identity_status, off.reuse_identity_id, off.review_required,
            [str(r) for r in off.reasons])


@given(cs=st.lists(candidates(), max_size=8), seed=st.integers(0, 10**6), first=names)
@hsettings(max_examples=150, suppress_health_check=[HealthCheck.too_slow])
def test_order_independence(cs, seed, first):
    n = norm(S, first, "ali", "1985-05-10", "+966 55 123 4567", "a@gir-synthetic.invalid")
    shuffled = list(cs)
    random.Random(seed).shuffle(shuffled)
    a, b = decide(n, cs, settings=S, **DIRECT), decide(n, shuffled, settings=S, **DIRECT)
    assert (a.decision, a.decision_type, a.reuse_identity_id, [str(r) for r in a.reasons]) == \
           (b.decision, b.decision_type, b.reuse_identity_id, [str(r) for r in b.reasons])
