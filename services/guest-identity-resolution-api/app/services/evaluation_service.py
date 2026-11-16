"""Evaluation, re-evaluation, commit and fail (plan sections 9.3, 9.5, 14.1-14.3, 14.5).

One short transaction per call; Python never calls CRM. Steps follow 9.5 exactly:
validate -> idempotency -> normalize -> lock + stale check -> upsert projection -> candidates ->
sharing flags -> rules (precedence) -> reserve pair -> persist decision (DECIDED_PENDING_CRM)."""
from __future__ import annotations

import dataclasses
import hashlib
import json
import logging
import time
from typing import Optional

from sqlalchemy.engine import Connection

from app.config import Settings
from app.db.crypto import Crypto
from app.db.session import lock
from app.domain.enums import Decision, DecisionType, IdentityLifecycle, IdentityStatus, ProcessingState
from app.domain.state_machine import check_processing
from app.domain.errors import ApiError, idempotency_conflict, invalid, invalid_state, not_found, stale_event
from app.domain.reason_codes import Reason
from app.observability import metrics
from app.observability.logging import log
from app.repositories import decisions as dec_repo
from app.repositories import guest_projection, identity_projection, review_cases, statistics
from app.schemas.events import GuestIdentityEvent, scope_agency
from app.services import candidate_retrieval
from app.services.decision_explainer import summary
from app.services.normalization import NormalizedIdentity, normalize_identity
from app.services.pair_allocator import PairAllocator
from app.services.rule_engine import RuleResult, decide, is_direct

logger = logging.getLogger("gir.evaluation")

STALE = {"_outcome": "STALE"}
_HASH_EXCLUDED = {"eventId", "correlationId", "idempotencyKey", "eventType"}


def idempotency_key(ev: GuestIdentityEvent) -> str:
    return f"{ev.sourceSystem}:{ev.sourceRecordId}:{ev.crmModifiedTime.astimezone().isoformat()}"


def payload_hash(ev: GuestIdentityEvent) -> str:
    data = {k: v for k, v in ev.model_dump(mode="json").items() if k not in _HASH_EXCLUDED}
    return hashlib.sha256(json.dumps(data, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def rule_checksum(settings: Settings) -> str:
    cfg = {k: getattr(settings, k) for k in (
        "certain_reuse_enabled", "four_field_review_enabled", "weighted_auto_enabled", "phone_tail_evidence_enabled",
        "shadow_only_enabled", "over_shared_threshold_version", "active_rule_version", "direct_source_codes",
        "direct_agency_names", "dob_placeholders", "dob_suspicious", "dob_suspicious_threshold", "dob_max_age_years",
        "name_placeholders", "email_placeholders", "email_placeholder_patterns", "phone_default_region",
        "accept_empty_agency", "phone_966_without_plus_is_e164", "phone_saudi_local_without_context",
        "over_shared_phone_threshold", "over_shared_email_threshold", "candidate_guardrail")}
    return hashlib.sha256(json.dumps(cfg, sort_keys=True, default=list).encode()).hexdigest()[:16]


class EvaluationService:
    def __init__(self, settings: Settings, crypto: Crypto, allocator: PairAllocator):
        self.s, self.crypto, self.allocator = settings, crypto, allocator

    # ------------------------------------------------------------------ evaluate / re-evaluate
    def evaluate(self, conn: Connection, ev: GuestIdentityEvent, kind: str = "EVALUATE") -> dict:
        started = time.monotonic()
        key = idempotency_key(ev)
        h = payload_hash(ev)
        lock(conn, "req:" + key)
        existing = dec_repo.request_by_key(conn, key, for_update=True)
        if existing:
            if existing["payload_hash"] != h:
                raise idempotency_conflict()
            dec_repo.bump_attempt(conn, existing["request_id"])
            if existing["state"] == ProcessingState.REJECTED_STALE.value:
                return STALE
            if existing["decision_id"]:
                return self.response(conn, existing["decision_id"])
            raise invalid_state("The earlier request for this key did not produce a decision.")

        norm = normalize_identity(ev.firstName, ev.lastName, ev.dateOfBirth, ev.phone, ev.email, ev.countryCode, self.s,
                                  citizenship=ev.citizenshipCode, alt_phone=ev.alternatePhone)
        agency = scope_agency(ev)
        direct = is_direct(ev.sourceCode, agency, ev.sourceSystem, self.s)
        lock(conn, "guest:" + ev.crmGuestRecordId)
        current = guest_projection.get(conn, ev.crmGuestRecordId, for_update=True)
        if current and current["crm_modified_time"] > ev.crmModifiedTime:
            dec_repo.insert_request(conn, key, h, kind, ev.crmGuestRecordId, ev.correlationId,
                                    ProcessingState.REJECTED_STALE.value)
            log(logger, "stale event rejected", correlationId=ev.correlationId)
            return STALE                   # the caller commits the REJECTED_STALE record, then answers 409
        request_id = dec_repo.insert_request(conn, key, h, kind, ev.crmGuestRecordId, ev.correlationId,
                                             ProcessingState.RECEIVED.value)

        # the Guest's current identity, if CRM already holds one (D04: it is never replaced automatically)
        current_identity: Optional[str] = current["identity_id"] if current else None
        if ev.currentIdentityId:
            current_identity = identity_projection.ensure_external(conn, self.crypto, ev.currentIdentityId,
                                                                   ev.currentGlobalId, ev.currentLoyaltyId,
                                                                   self.s.active_rule_version)
        crm_identity = ev.currentIdentityId or (current["crm_identity_record_id"] if current else None)
        guest_projection.upsert(conn, self.crypto, ev, norm, direct, identity_id=current_identity,
                                crm_identity_record_id=crm_identity if current_identity else None)

        # serialize concurrent Guests that could resolve to the same identity (9.3)
        lock(conn, *self._block_keys(norm))
        over_phones = statistics.over_shared_phones(conn, norm.high_phones(), self.s.over_shared_phone_threshold,
                                                    self.s.over_shared_threshold_version)
        over_email = statistics.refresh(conn, "EMAIL", norm.email.key, self.s.over_shared_email_threshold,
                                        self.s.over_shared_threshold_version)
        if norm.dob.suspicious and statistics.refresh(conn, "DOB", norm.dob.key, self.s.dob_suspicious_threshold,
                                                      self.s.over_shared_threshold_version):
            # a suspicious DOB shared by too many identities is treated as a placeholder
            norm = dataclasses.replace(norm, dob=dataclasses.replace(norm.dob, key=None, placeholder=True))
        cands, exceeded = candidate_retrieval.retrieve(conn, norm, ev.crmGuestRecordId, current_identity,
                                                       self.s.candidate_guardrail)
        metrics.CANDIDATES.observe(len(cands))
        result = decide(norm, cands, source_code=ev.sourceCode, agency_code=agency,
                        source_system=ev.sourceSystem, settings=self.s,
                        over_shared_phones=over_phones,
                        over_shared_emails={norm.email.key} if over_email else set(),
                        guardrail_exceeded=exceeded)

        if current_identity and result.decision is not Decision.EXCLUDED_NON_DIRECT:
            result = self._keep_existing(result)
        decision_id = dec_repo.new_decision_id()
        shadow_only = self.s.shadow_only_enabled and result.decision is not Decision.EXCLUDED_NON_DIRECT
        if shadow_only:
            # rollout step 1 (22.2): record what would happen; reserve nothing, link nothing, tell CRM nothing
            identity_id, reserved, case_id = current_identity, False, None
            result = dataclasses.replace(result, reasons=list(result.reasons) + [Reason.SHADOW_ONLY_NOT_APPLIED])
            crm_update = False
        else:
            identity_id, reserved = self._apply(conn, ev, result, decision_id, current_identity)
            case_id = None                     # the case references the decision, so it is created after it
            crm_update = result.decision is not Decision.EXCLUDED_NON_DIRECT and not (
                result.decision is Decision.KEEP_EXISTING_IDENTITY and not result.review_required)
        state = ProcessingState.DECIDED_PENDING_CRM if crm_update else ProcessingState.COMMITTED
        dec_repo.insert_decision(
            conn, decision_id=decision_id, request_id=request_id, crm_guest_record_id=ev.crmGuestRecordId,
            decision=result.decision.value, decision_type=result.decision_type.value,
            identity_status=result.identity_status.value, identity_id=identity_id, reserved_new_pair=reserved,
            review_required=result.review_required and not shadow_only, review_case_id=case_id,
            crm_update_required=crm_update,
            rule_version=self.s.active_rule_version, rule_checksum=rule_checksum(self.s),
            reason_codes=[str(r) for r in result.reasons],
            candidate_refs=[{"crmGuestRecordId": e.candidate.crm_guest_record_id,
                             "identityId": e.candidate.identity_id} for e in result.candidates],
            shadow=result.shadow, summary=summary(result), state=state.value, correlation_id=ev.correlationId)
        if result.review_required and not shadow_only:
            case_id = self._open_case(conn, ev, result, decision_id, identity_id)
            dec_repo.update_decision(conn, decision_id, review_case_id=case_id)
        dec_repo.update_request(conn, request_id, state=state.value, decision_id=decision_id)
        metrics.DECISIONS.labels(result.decision.value, result.decision_type.value, self.s.active_rule_version).inc()
        metrics.DURATION.observe(time.monotonic() - started)
        log(logger, "decision", correlationId=ev.correlationId, decisionId=decision_id, decision=result.decision.value,
            decisionType=result.decision_type.value, reasonCodes=[str(r) for r in result.reasons],
            candidates=len(cands), ruleVersion=self.s.active_rule_version)
        return self.response(conn, decision_id)

    def _block_keys(self, norm: NormalizedIdentity) -> list[str]:
        keys = []
        if norm.first.canonical and norm.last.canonical and norm.dob.key:
            keys.append(f"blk:fld:{norm.first.canonical}|{norm.last.canonical}|{norm.dob.key}")
        keys += ["blk:ph:" + p for p in sorted(norm.high_phones())]
        if norm.email.key:
            keys.append("blk:em:" + norm.email.key)
        return keys

    def _keep_existing(self, result: RuleResult) -> RuleResult:
        """Re-evaluation of a Guest that already has a pair (14.3, D04): IDs never change
        automatically; a new conflict opens a review case, a harmless correction does not."""
        conflict = (result.decision is Decision.REUSE_EXISTING_IDENTITY or result.review_required)
        reasons = [Reason.EXISTING_IDENTITY_KEPT] + ([Reason.REEVALUATION_CONFLICT] + list(result.reasons) if conflict else [])
        from app.domain.enums import ReviewKind
        return RuleResult(Decision.KEEP_EXISTING_IDENTITY, DecisionType.NONE,
                          IdentityStatus.NEW_IDENTITY_PENDING_REVIEW if conflict else IdentityStatus.IDENTITY_REUSED_CERTAIN,
                          review_required=conflict, review_kind=ReviewKind.REEVALUATION_CONFLICT if conflict else None,
                          review_priority=("HIGH" if result.review_kind and result.review_kind.value ==
                                           "MULTIPLE_IDENTITY_CONFLICT" else "NORMAL") if conflict else None,
                          reasons=reasons, candidates=result.candidates if conflict else [], shadow=result.shadow)

    def _apply(self, conn: Connection, ev, result: RuleResult, decision_id: str,
               current_identity: Optional[str]) -> tuple[Optional[str], bool]:
        if result.decision is Decision.KEEP_EXISTING_IDENTITY:
            return current_identity, False
        if result.decision is Decision.REUSE_EXISTING_IDENTITY:
            ident = identity_projection.get(conn, result.reuse_identity_id)
            guest_projection.set_identity(conn, ev.crmGuestRecordId, result.reuse_identity_id,
                                          ident["crm_identity_record_id"] if ident else None)
            return result.reuse_identity_id, False
        if result.needs_new_pair:
            global_id, loyalty_id = self.allocator.allocate(conn)
            process = "REVIEW" if result.provisional else "NEW"
            identity_id = identity_projection.create_reserved(conn, self.crypto, decision_id, global_id, loyalty_id,
                                                              process, self.s.active_rule_version)
            # linked now so concurrent Guests see a not-ready identity; reusable only after commit
            guest_projection.set_identity(conn, ev.crmGuestRecordId, identity_id, None)
            return identity_id, True
        return None, False

    def _open_case(self, conn: Connection, ev, result: RuleResult, decision_id: str,
                   identity_id: Optional[str]) -> str:
        case_id = review_cases.new_case_id()
        review_cases.create(conn, case_id, ev.crmGuestRecordId, identity_id if result.provisional else None,
                            decision_id, result.review_kind.value, result.review_priority or "NORMAL",
                            self.s.active_rule_version, [str(r) for r in result.reasons])
        review_cases.replace_candidates(conn, case_id, [
            {"crm_guest_record_id": e.candidate.crm_guest_record_id, "identity_id": e.candidate.identity_id,
             "crm_identity_record_id": e.candidate.crm_identity_record_id, "field_results": e.fields,
             "reason_codes": [str(r) for r in e.reasons], "shadow": e.shadow}
            for e in result.candidates])
        return case_id

    # ------------------------------------------------------------------ response / commit / fail
    def response(self, conn: Connection, decision_id: str) -> dict:
        d = dec_repo.get_decision(conn, decision_id)
        if not d:
            raise not_found("Decision")
        ident = identity_projection.get(conn, d["identity_id"]) if d["identity_id"] else None
        global_id, loyalty_id = identity_projection.pair(self.crypto, ident)
        priority = None
        if d["review_case_id"]:
            case = review_cases.get(conn, d["review_case_id"])
            priority = case["priority"] if case else None
        return {"decisionId": d["decision_id"], "decision": d["decision"], "decisionType": d["decision_type"],
                "identityStatus": d["identity_status"],
                "crmIdentityRecordId": ident["crm_identity_record_id"] if ident else None,
                "identityId": d["identity_id"], "globalId": global_id, "loyaltyId": loyalty_id,
                "provisional": d["decision"] == Decision.CREATE_PROVISIONAL_IDENTITY.value,
                "reviewRequired": d["review_required"], "reviewCaseId": d["review_case_id"],
                "reviewPriority": priority, "crmUpdateRequired": d["crm_update_required"],
                "ruleVersion": d["rule_version"], "reasonCodes": list(d["reason_codes"]),
                "reasonSummary": d["summary"], "processingState": d["state"], "shadow": d["shadow"]}

    def commit(self, conn: Connection, decision_id: str, crm_identity_record_id: Optional[str]) -> dict:
        d = dec_repo.get_decision(conn, decision_id, for_update=True)
        if not d:
            raise not_found("Decision")
        if d["state"] == ProcessingState.COMMITTED.value:
            return self.response(conn, decision_id)               # repeated commit is idempotent
        check_processing(d["state"], ProcessingState.COMMITTED)
        ident = identity_projection.get(conn, d["identity_id"], for_update=True) if d["identity_id"] else None
        if d["reserved_new_pair"]:
            if not crm_identity_record_id:
                raise invalid("crmIdentityRecordId is required to commit a newly reserved identity.")
            lifecycle = (IdentityLifecycle.PROVISIONAL if d["decision"] == Decision.CREATE_PROVISIONAL_IDENTITY.value
                         else IdentityLifecycle.ACTIVE)
            identity_projection.commit(conn, d["identity_id"], crm_identity_record_id, lifecycle)
            guest_projection.set_identity(conn, d["crm_guest_record_id"], d["identity_id"], crm_identity_record_id)
        elif ident:
            guest_projection.set_identity(conn, d["crm_guest_record_id"], d["identity_id"], ident["crm_identity_record_id"])
        row = guest_projection.get(conn, d["crm_guest_record_id"])
        if row:
            statistics.over_shared_phones(conn, {row["phone_e164_key"], row["alt_phone_e164_key"]} - {None},
                                          self.s.over_shared_phone_threshold, self.s.over_shared_threshold_version)
            statistics.refresh(conn, "EMAIL", row["email_key"], self.s.over_shared_email_threshold,
                               self.s.over_shared_threshold_version)
        dec_repo.update_decision(conn, decision_id, state=ProcessingState.COMMITTED.value, error_code=None)
        dec_repo.update_request(conn, d["request_id"], state=ProcessingState.COMMITTED.value)
        return self.response(conn, decision_id)

    def fail(self, conn: Connection, decision_id: str, retryable: bool, error_code: str) -> dict:
        d = dec_repo.get_decision(conn, decision_id, for_update=True)
        if not d:
            raise not_found("Decision")
        state = ProcessingState.CRM_UPDATE_FAILED if retryable else ProcessingState.FAILED
        check_processing(d["state"], state)
        # the reserved pair stays bound to this decision: never reusable, never regenerated
        dec_repo.update_decision(conn, decision_id, state=state.value, error_code=error_code)
        dec_repo.update_request(conn, d["request_id"], state=state.value, error_code=error_code)
        return self.response(conn, decision_id)
