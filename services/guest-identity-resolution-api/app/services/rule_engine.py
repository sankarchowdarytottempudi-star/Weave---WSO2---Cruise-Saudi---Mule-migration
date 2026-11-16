"""Phase 1 rule engine (plan sections 12 and 9.5 step 8). Pure functions, no I/O.

Precedence, exactly:
  0. not direct-scope                                  -> EXCLUDED_NON_DIRECT (no identity action)
  0b. candidate guardrail exceeded                     -> provisional pair + GUARDRAIL review
  1. several distinct identities pass CERTAIN          -> MULTIPLE_IDENTITY_CONFLICT (provisional, high priority)
  2. one distinct identity passes CERTAIN
       complete conflict-free reusable pair            -> REUSE_EXISTING_IDENTITY (CERTAIN_PHONE / CERTAIN_EMAIL)
       otherwise                                       -> provisional pair + PAIR_REPAIR review
  3. CERTAIN did not pass, four exact valid fields     -> FOUR_FIELD_REVIEW (provisional)
  4. otherwise                                         -> CREATE_NEW_IDENTITY (permanent)
The weighted / Jaro-Winkler model is computed afterwards and returned as shadow evidence only.
The output is independent of candidate order (identity ids are sorted before any tie)."""
from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date
from typing import Iterable, Optional

from app.config import Settings
from app.domain.enums import (Decision, DecisionType, FieldResult, IdentityStatus, PairIntegrity,
                              ReviewKind)
from app.domain.reason_codes import Reason
from app.services.normalization import NormalizedIdentity
from app.services.shadow import shadow_score


@dataclass(frozen=True)
class Candidate:
    """One candidate CRM Guest row from the index (already normalized)."""
    crm_guest_record_id: str
    identity_id: Optional[str]                 # internal identity id; None = no identity linked
    first: Optional[str]
    last: Optional[str]
    dob: Optional[date]
    phone_e164: Optional[str]                  # only HIGH-confidence numbers are stored here
    phone_tail: Optional[str]
    email: Optional[str]
    pair_integrity: Optional[PairIntegrity]    # of the linked identity; None = no identity
    reusable: bool                             # complete, conflict-free, committed, active
    crm_identity_record_id: Optional[str] = None
    alt_phone_e164: Optional[str] = None       # second phone field (CRM Phone vs Mobile)
    alt_phone_tail: Optional[str] = None


@dataclass(frozen=True)
class CandidateEvaluation:
    candidate: Candidate
    fields: dict
    certain: bool
    certain_via: Optional[str]                 # "phone" | "email"
    exact_count: int
    reasons: tuple
    shadow: dict


@dataclass
class RuleResult:
    decision: Decision
    decision_type: DecisionType
    identity_status: IdentityStatus
    reuse_identity_id: Optional[str] = None
    needs_new_pair: bool = False
    provisional: bool = False
    review_required: bool = False
    review_kind: Optional[ReviewKind] = None
    review_priority: Optional[str] = None
    reasons: list = field(default_factory=list)
    candidates: list = field(default_factory=list)          # CandidateEvaluation for review evidence
    shadow: Optional[dict] = None


def scope_key(value: Optional[str]) -> str:
    """Exact comparison after trim + case-fold (whitespace inside is collapsed to one space)."""
    return " ".join((value or "").split()).casefold()


def is_direct(source_code: Optional[str], agency_name: Optional[str], source_system: str, settings: Settings) -> bool:
    """Section 12.1 with the owner-approved lists: the source code AND the AROYA agency name must
    both be in scope. The source code alone admits dozens of agencies; INT-AGENT is out of scope.
    accept_empty_agency (owner decision pending) admits a direct source code with a blank agency."""
    sc, ag = scope_key(source_code), scope_key(agency_name)
    if not sc or sc not in {scope_key(c) for c in settings.direct_source_codes}:
        return False
    if not ag:
        return settings.accept_empty_agency
    return ag in {scope_key(a) for a in settings.direct_agency_names}


def _field(a, b) -> FieldResult:
    if a is None or b is None:
        return FieldResult.MISSING
    return FieldResult.EXACT if a == b else FieldResult.CONFLICT


def evaluate_candidate(incoming: NormalizedIdentity, c: Candidate, over_shared_phones: set,
                       over_shared_emails: set) -> CandidateEvaluation:
    reasons: list = []
    first = _field(incoming.first.canonical, c.first)
    last = _field(incoming.last.canonical, c.last)
    dob = _field(incoming.dob.key, c.dob)
    if incoming.dob.placeholder:
        reasons.append(Reason.PLACEHOLDER_DOB_SUPPRESSED)
    # phone: both fields (Mobile, Phone); only HIGH-confidence E.164 numbers count; over-shared numbers count zero
    incoming_high = incoming.high_phones()
    usable = incoming_high - set(over_shared_phones)
    cand_phones = {p for p in (c.phone_e164, c.alt_phone_e164) if p}
    supplied = any(p.original not in (None, "") for p in (incoming.phone, incoming.alt_phone))
    if usable & cand_phones:
        phone = FieldResult.EXACT
    elif incoming_high and not usable:
        phone = FieldResult.SUPPRESSED
        reasons.append(Reason.OVER_SHARED_PHONE_SUPPRESSED)
    elif not incoming_high and supplied and cand_phones:
        phone = FieldResult.LOW_CONFIDENCE
    elif usable and cand_phones:
        phone = FieldResult.CONFLICT
    else:
        phone = FieldResult.MISSING
    tails_in = {p.tail for p in (incoming.phone, incoming.alt_phone) if p.tail}
    tails_c = {t for t in (c.phone_tail, c.alt_phone_tail) if t}
    if phone is not FieldResult.EXACT and tails_in & tails_c:
        reasons.append(Reason.PHONE_TAIL_MATCH_SHADOW_ONLY)
    if incoming.email.key and incoming.email.key in over_shared_emails:
        email = FieldResult.SUPPRESSED
        reasons.append(Reason.OVER_SHARED_EMAIL_SUPPRESSED)
    else:
        email = _field(incoming.email.key, c.email)
    results = {"firstName": first, "lastName": last, "dateOfBirth": dob, "phone": phone, "email": email}
    exact = sum(1 for v in results.values() if v is FieldResult.EXACT)
    if first is FieldResult.EXACT:
        reasons.append(Reason.EXACT_CANONICAL_FIRST_NAME)
    if last is FieldResult.EXACT:
        reasons.append(Reason.EXACT_CANONICAL_LAST_NAME)
    if dob is FieldResult.EXACT:
        reasons.append(Reason.EXACT_REAL_DOB)
    if phone is FieldResult.EXACT:
        reasons.append(Reason.PERSONAL_E164_PHONE_MATCH)
    if email is FieldResult.EXACT:
        reasons.append(Reason.PERSONAL_EMAIL_MATCH)
    names_dob = first is FieldResult.EXACT and last is FieldResult.EXACT and dob is FieldResult.EXACT
    via = None
    if names_dob and phone is FieldResult.EXACT:
        via = "phone"
    elif names_dob and email is FieldResult.EXACT:
        via = "email"
    shadow = shadow_score(incoming.first.canonical, c.first, incoming.last.canonical, c.last,
                          dob is FieldResult.EXACT, phone is FieldResult.EXACT, email is FieldResult.EXACT)
    return CandidateEvaluation(candidate=c, fields={k: v.value for k, v in results.items()}, certain=via is not None,
                               certain_via=via, exact_count=exact, reasons=tuple(dict.fromkeys(reasons)), shadow=shadow)


def _identity_key(c: Candidate) -> str:
    # a Guest row without an identity is its own (not-ready) identity for counting purposes
    return c.identity_id or f"guest:{c.crm_guest_record_id}"


def decide(incoming: NormalizedIdentity, candidates: Iterable[Candidate], *, source_code: Optional[str],
           agency_code: Optional[str], source_system: str, settings: Settings,
           over_shared_phones: Optional[set] = None, over_shared_emails: Optional[set] = None,
           guardrail_exceeded: bool = False) -> RuleResult:
    over_shared_phones = over_shared_phones or set()
    over_shared_emails = over_shared_emails or set()
    if not is_direct(source_code, agency_code, source_system, settings):
        return RuleResult(Decision.EXCLUDED_NON_DIRECT, DecisionType.NONE, IdentityStatus.EXCLUDED_NON_DIRECT,
                          reasons=[Reason.EXCLUDED_NON_DIRECT])
    evaluations = [evaluate_candidate(incoming, c, over_shared_phones, over_shared_emails)
                   for c in sorted(candidates, key=lambda x: (_identity_key(x), x.crm_guest_record_id))]
    best_shadow = max((e.shadow for e in evaluations), key=lambda s: s["score"], default=None) \
        if settings.weighted_shadow_enabled else None

    if guardrail_exceeded:
        return RuleResult(Decision.CREATE_PROVISIONAL_IDENTITY, DecisionType.GUARDRAIL,
                          IdentityStatus.NEW_IDENTITY_PENDING_REVIEW, needs_new_pair=True, provisional=True,
                          review_required=True, review_kind=ReviewKind.GUARDRAIL, review_priority="HIGH",
                          reasons=[Reason.CANDIDATE_GUARDRAIL_EXCEEDED], candidates=evaluations, shadow=best_shadow)

    certain_by_identity: dict = {}
    for e in evaluations:
        if e.certain:
            certain_by_identity.setdefault(_identity_key(e.candidate), []).append(e)
    certain_ids = sorted(certain_by_identity)

    if settings.certain_reuse_enabled and len(certain_ids) > 1:
        return RuleResult(Decision.CREATE_PROVISIONAL_IDENTITY, DecisionType.MULTIPLE_IDENTITY,
                          IdentityStatus.MULTIPLE_IDENTITY_CONFLICT, needs_new_pair=True, provisional=True,
                          review_required=True, review_kind=ReviewKind.MULTIPLE_IDENTITY_CONFLICT,
                          review_priority="HIGH", reasons=[Reason.MULTIPLE_DISTINCT_IDENTITIES],
                          candidates=[e for e in evaluations if e.certain], shadow=best_shadow)

    if settings.certain_reuse_enabled and len(certain_ids) == 1:
        rows = certain_by_identity[certain_ids[0]]
        head = rows[0]
        evidence = [Reason.EXACT_CANONICAL_NAMES, Reason.EXACT_REAL_DOB]
        via_phone = any(r.certain_via == "phone" for r in rows)
        evidence.append(Reason.PERSONAL_E164_PHONE_MATCH if via_phone else Reason.PERSONAL_EMAIL_MATCH)
        if head.candidate.reusable and all(r.candidate.reusable for r in rows):
            return RuleResult(Decision.REUSE_EXISTING_IDENTITY,
                              DecisionType.CERTAIN_PHONE if via_phone else DecisionType.CERTAIN_EMAIL,
                              IdentityStatus.IDENTITY_REUSED_CERTAIN, reuse_identity_id=head.candidate.identity_id,
                              reasons=evidence + [Reason.ONE_DISTINCT_REUSABLE_IDENTITY], candidates=rows,
                              shadow=best_shadow)
        why = (Reason.CURRENT_ID_MAPPING_CONFLICT if head.candidate.pair_integrity is PairIntegrity.CONFLICT
               else Reason.MATCHED_IDENTITY_NOT_READY)
        return RuleResult(Decision.CREATE_PROVISIONAL_IDENTITY, DecisionType.PAIR_REPAIR,
                          IdentityStatus.PAIR_REPAIR_REQUIRED, needs_new_pair=True, provisional=True,
                          review_required=True, review_kind=ReviewKind.PAIR_REPAIR, review_priority="NORMAL",
                          reasons=evidence + [why], candidates=rows, shadow=best_shadow)

    four = [e for e in evaluations if e.exact_count >= 4]
    if settings.four_field_review_enabled and four:
        return RuleResult(Decision.CREATE_PROVISIONAL_IDENTITY, DecisionType.FOUR_FIELD,
                          IdentityStatus.NEW_IDENTITY_PENDING_REVIEW, needs_new_pair=True, provisional=True,
                          review_required=True, review_kind=ReviewKind.FOUR_FIELD_REVIEW, review_priority="NORMAL",
                          reasons=[Reason.FOUR_EXACT_VALID_FIELDS], candidates=four, shadow=best_shadow)

    return RuleResult(Decision.CREATE_NEW_IDENTITY, DecisionType.NEW, IdentityStatus.NEW_IDENTITY_CREATED,
                      needs_new_pair=True, reasons=[Reason.NO_DETERMINISTIC_CANDIDATE],
                      candidates=[e for e in evaluations if e.shadow["score"] >= 0.78], shadow=best_shadow)
