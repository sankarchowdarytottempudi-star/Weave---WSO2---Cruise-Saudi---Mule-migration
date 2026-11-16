"""Plan section 21.4 - mandatory matching acceptance cases, one named test each (rule level).
Cases 11-13 need the database and live in tests/integration/test_acceptance_21_4_db.py."""
from datetime import date

from app.domain.enums import Decision, DecisionType, FieldResult, PairIntegrity
from app.domain.reason_codes import Reason
from app.services.rule_engine import Candidate, decide
from tests.conftest import norm

DIRECT = dict(source_code="MOBAPP", agency_code="AROYA CRUISES MAIN OFFICE", source_system="SEAWARE")


def cand(gid="R200", ident="I-1", first="muhammad", last="ali", dob=date(1985, 5, 10), phone="+966551234567",
         email="muhammad.ali@gir-synthetic.invalid", integrity=PairIntegrity.COMPLETE, reusable=True, tail=None):
    return Candidate(gid, ident, first, last, dob, phone, tail or (phone[-9:] if phone else None), email,
                     integrity if ident else None, reusable if ident else False, "CRM-" + (ident or "none"))


def run(settings, incoming, cands, **kw):
    return decide(incoming, cands, settings=settings, **DIRECT, **kw)


def test_21_4_01_certain_phone_reuses_one_identity_when_email_blank(settings):
    r = run(settings, norm(settings, email=None), [cand(email=None)])
    assert r.decision is Decision.REUSE_EXISTING_IDENTITY and r.decision_type is DecisionType.CERTAIN_PHONE
    assert r.reuse_identity_id == "I-1" and not r.review_required and not r.needs_new_pair
    assert Reason.PERSONAL_E164_PHONE_MATCH in r.reasons


def test_21_4_02_certain_email_reuses_one_identity_when_phone_blank(settings):
    r = run(settings, norm(settings, phone=None), [cand(phone=None)])
    assert r.decision is Decision.REUSE_EXISTING_IDENTITY and r.decision_type is DecisionType.CERTAIN_EMAIL
    assert Reason.PERSONAL_EMAIL_MATCH in r.reasons


def test_21_4_03_four_exact_fields_with_conflicting_dob_create_review_and_provisional_pair(settings):
    r = run(settings, norm(settings), [cand(dob=date(1986, 5, 10))])
    assert r.decision is Decision.CREATE_PROVISIONAL_IDENTITY and r.decision_type is DecisionType.FOUR_FIELD
    assert r.review_required and r.provisional and r.needs_new_pair
    assert r.candidates[0].fields["dateOfBirth"] == FieldResult.CONFLICT.value


def test_21_4_04_fuzzy_first_name_plus_four_exact_creates_review_not_reuse(settings):
    r = run(settings, norm(settings, first="Mohammed"), [cand()])
    assert r.decision is Decision.CREATE_PROVISIONAL_IDENTITY and r.decision_type is DecisionType.FOUR_FIELD
    assert r.reuse_identity_id is None


def test_21_4_05_tail_only_phone_does_not_satisfy_certain(settings):
    # same last 9 digits, different country code; email blank on both
    r = run(settings, norm(settings, email=None), [cand(phone="+971551234567", email=None, tail="551234567")])
    assert r.decision is not Decision.REUSE_EXISTING_IDENTITY
    assert any(Reason.PHONE_TAIL_MATCH_SHADOW_ONLY in e.reasons for e in r.candidates) or r.decision is Decision.CREATE_NEW_IDENTITY


def test_21_4_06a_over_shared_phone_contributes_zero(settings):
    n = norm(settings, email=None)
    r = run(settings, n, [cand(email=None)], over_shared_phones={n.phone.e164})
    assert r.decision is Decision.CREATE_NEW_IDENTITY


def test_21_4_06b_over_shared_email_contributes_zero_but_personal_phone_still_counts(settings):
    n = norm(settings)
    r = run(settings, n, [cand(phone=None)], over_shared_emails={n.email.key})
    assert r.decision is Decision.CREATE_NEW_IDENTITY
    r2 = run(settings, n, [cand()], over_shared_emails={n.email.key})
    assert r2.decision is Decision.REUSE_EXISTING_IDENTITY and r2.decision_type is DecisionType.CERTAIN_PHONE


def test_21_4_07_blank_against_blank_never_counts_as_agreement(settings):
    n = norm(settings, dob=None, phone=None, email=None)
    r = run(settings, n, [cand(dob=None, phone=None, email=None)])
    assert r.decision is Decision.CREATE_NEW_IDENTITY
    fields = r.candidates[0].fields if r.candidates else None
    if fields:
        assert fields["dateOfBirth"] == fields["phone"] == fields["email"] == FieldResult.MISSING.value


def test_21_4_08_several_qualifying_rows_under_one_identity_reuse_that_identity(settings):
    r = run(settings, norm(settings), [cand("R200"), cand("R201"), cand("R202", email=None)])
    assert r.decision is Decision.REUSE_EXISTING_IDENTITY and r.reuse_identity_id == "I-1"


def test_21_4_09_several_qualifying_distinct_identities_create_conflict_review(settings):
    r = run(settings, norm(settings), [cand("R200", "I-1"), cand("R300", "I-2")])
    assert r.decision is Decision.CREATE_PROVISIONAL_IDENTITY
    assert r.decision_type is DecisionType.MULTIPLE_IDENTITY and r.review_priority == "HIGH"
    assert Reason.MULTIPLE_DISTINCT_IDENTITIES in r.reasons


def test_21_4_10a_incomplete_existing_pair_is_never_reused(settings):
    r = run(settings, norm(settings), [cand(integrity=PairIntegrity.INCOMPLETE, reusable=False)])
    assert r.decision is Decision.CREATE_PROVISIONAL_IDENTITY and r.decision_type is DecisionType.PAIR_REPAIR
    assert Reason.MATCHED_IDENTITY_NOT_READY in r.reasons


def test_21_4_10b_conflicting_existing_pair_is_never_reused(settings):
    r = run(settings, norm(settings), [cand(integrity=PairIntegrity.CONFLICT, reusable=False)])
    assert r.decision_type is DecisionType.PAIR_REPAIR and Reason.CURRENT_ID_MAPPING_CONFLICT in r.reasons


def test_21_4_14_weighted_score_above_092_remains_shadow_only(settings):
    # fuzzy first name + four exact fields: shadow score is well above 0.92, production still only
    # opens a four-field review and never reuses automatically
    r = run(settings, norm(settings, first="Mohammad"), [cand()])
    assert r.shadow["score"] >= 0.92 and r.shadow["label"] == "SHADOW_AUTO_CANDIDATE"
    assert r.decision is Decision.CREATE_PROVISIONAL_IDENTITY and r.decision_type is DecisionType.FOUR_FIELD
    assert r.reuse_identity_id is None and not settings.weighted_auto_enabled


# ---- further rules ----
def test_excluded_non_direct_has_no_identity_action(settings):
    r = decide(norm(settings), [cand()], source_code="INT-AGENT", agency_code="AROYA CRUISES MAIN OFFICE",
               source_system="SEAWARE", settings=settings)
    assert r.decision is Decision.EXCLUDED_NON_DIRECT and not r.needs_new_pair


def test_guardrail_creates_provisional_review(settings):
    r = run(settings, norm(settings), [cand()], guardrail_exceeded=True)
    assert r.decision_type is DecisionType.GUARDRAIL and r.review_required and r.review_priority == "HIGH"


def test_certain_reuse_disabled_falls_to_four_field_review(settings):
    import dataclasses
    s = dataclasses.replace(settings, certain_reuse_enabled=False)
    r = run(s, norm(s), [cand()])
    assert r.decision_type is DecisionType.FOUR_FIELD


def test_all_rules_disabled_gives_new_pair(settings):
    import dataclasses
    s = dataclasses.replace(settings, certain_reuse_enabled=False, four_field_review_enabled=False)
    assert run(s, norm(s), [cand()]).decision is Decision.CREATE_NEW_IDENTITY


def test_placeholder_dob_is_suppressed_and_blocks_certain(settings):
    r = run(settings, norm(settings, dob="1900-01-01"), [cand(dob=None)])
    assert r.decision is not Decision.REUSE_EXISTING_IDENTITY
    assert any(Reason.PLACEHOLDER_DOB_SUPPRESSED in e.reasons for e in r.candidates) or r.candidates == []


def test_low_confidence_phone_never_counts(settings):
    r = run(settings, norm(settings, phone="0551234567", email=None), [cand(email=None)])
    assert r.decision is not Decision.REUSE_EXISTING_IDENTITY


def test_shadow_disabled_stores_no_shadow(settings):
    import dataclasses
    s = dataclasses.replace(settings, weighted_shadow_enabled=False)
    assert run(s, norm(s), [cand()]).shadow is None


def test_alternate_phone_field_counts_as_phone_evidence(settings):
    from app.services.normalization import normalize_identity
    from tests.conftest import TODAY
    n = normalize_identity("Muhammad", "Ali", "1985-05-10", None, None, None, settings, today=TODAY,
                           alt_phone="966551234567")
    r = run(settings, n, [cand(email=None)])
    assert r.decision is Decision.REUSE_EXISTING_IDENTITY and r.decision_type is DecisionType.CERTAIN_PHONE
    c2 = Candidate("R9", "I-9", "muhammad", "ali", date(1985, 5, 10), None, None, None, PairIntegrity.COMPLETE, True,
                   "CRM-I-9", alt_phone_e164="+966551234567", alt_phone_tail="551234567")
    r2 = run(settings, norm(settings, email=None), [c2])
    assert r2.decision is Decision.REUSE_EXISTING_IDENTITY and r2.reuse_identity_id == "I-9"
