"""DB-backed manual review (plan sections 9.6, 9.7, 14.4, 15).

The review case is read from PostgreSQL only - this module has no CRM client and never needs one.
A manual decision is PREPARED here; the Integration Service performs the single final CRM read and
then calls freshness-failed or commit. Roles follow section 15.3."""
from __future__ import annotations

from typing import Optional

from sqlalchemy.engine import Connection

from app.config import Settings
from app.db.crypto import Crypto
from app.db.session import lock
from app.domain.enums import IdentityLifecycle, IdentityStatus, ReviewerAction, ReviewState
from app.domain.state_machine import check_review
from app.domain.errors import ApiError, forbidden, idempotency_conflict, invalid, invalid_state, not_found
from app.domain.reason_codes import Reason
from app.observability import metrics
from app.repositories import guest_projection, identity_projection, review_cases, statistics
from app.schemas.review import DecisionPreparationRequest, FreshnessFailedRequest
from app.services import candidate_retrieval
from app.services.normalization import normalize_identity
from app.services.rule_engine import decide

REVIEWER, SUPERVISOR = "IDENTITY_REVIEWER", "IDENTITY_SUPERVISOR"
CRM_ADMIN, AUDIT = "CRM_ADMINISTRATOR", "AUDIT_REPORTING"
VIEW_ROLES = {REVIEWER, SUPERVISOR, AUDIT, CRM_ADMIN}
COMMENT_ROLES = {REVIEWER, SUPERVISOR, CRM_ADMIN}
DISPLAY_ROLES = {REVIEWER, SUPERVISOR}          # audit sees evidence and history, not protected values
DECIDE_ROLES = {REVIEWER, SUPERVISOR}
COMPARE_FIELDS = ["firstName", "lastName", "dateOfBirth", "phone", "alternatePhone", "email", "guestIdentityId"]
OPEN_STATES = {ReviewState.REVIEW_OPEN.value, ReviewState.REVIEW_DATA_CHANGED.value}
_STATUS_FOR = {
    ReviewerAction.CONFIRM_SAME_PERSON: IdentityStatus.CONFIRMED_SAME_PERSON,
    ReviewerAction.CONFIRM_DIFFERENT_PEOPLE: IdentityStatus.CONFIRMED_DIFFERENT_PERSON,
    ReviewerAction.CONFIRM_HOUSEHOLD: IdentityStatus.HOUSEHOLD_RELATIONSHIP,
    ReviewerAction.DEFER: IdentityStatus.NEW_IDENTITY_PENDING_REVIEW,
    ReviewerAction.REVERSE_DECISION: IdentityStatus.CONFIRMED_SAME_PERSON,
}


def _iso(t) -> Optional[str]:
    return t.isoformat().replace("+00:00", "Z") if t else None


class ReviewService:
    def __init__(self, settings: Settings, crypto: Crypto):
        self.s, self.crypto = settings, crypto

    # ------------------------------------------------------------------ read (9.6)
    def get_case(self, conn: Connection, case_id: str, roles: set[str]) -> dict:
        if not roles & VIEW_ROLES:
            raise forbidden()
        case = review_cases.get(conn, case_id)
        if not case:
            raise not_found("Review case")
        show = bool(roles & DISPLAY_ROLES)
        incoming = guest_projection.get(conn, case["crm_guest_record_id"])
        prov = identity_projection.get(conn, case["provisional_identity_id"]) if case["provisional_identity_id"] else None
        out = {"caseId": case["case_id"], "caseStatus": case["state"], "kind": case["kind"],
               "priority": case["priority"], "ruleVersion": case["rule_version"],
               "reasonCodes": list(case["reason_codes"]), "lastResult": case["last_result"],
               "followUpDate": case["follow_up_date"].isoformat() if case["follow_up_date"] else None,
               "slaBusinessDays": self.s.sla_four_field_days if case["kind"] == "FOUR_FIELD_REVIEW"
               else self.s.sla_conflict_days, "escalateTo": SUPERVISOR,
               "slaDueTime": _iso(case["sla_due_time"]), "assignedTo": case["assigned_to"],
               "comments": self._comments(conn, case_id, show),
               "createdTime": _iso(case["created_time"]),
               "incoming": self._guest_view(incoming, show),
               "provisionalIdentity": self._identity_view(prov, show), "candidates": []}
        for c in review_cases.candidates(conn, case_id):
            g = guest_projection.get(conn, c["crm_guest_record_id"])
            ident = identity_projection.get(conn, c["identity_id"]) if c["identity_id"] else None
            view = self._guest_view(g, show)
            view.update({"crmIdentityRecordId": c["crm_identity_record_id"],
                         "identityId": str(c["identity_id"]) if c["identity_id"] else None,
                         "identity": self._identity_view(ident, show), "fieldResults": c["field_results"],
                         "reasonCodes": list(c["reason_codes"]), "shadow": c["shadow"]})
            out["candidates"].append(view)
        return out

    def _guest_view(self, row, show: bool) -> dict:
        if not row:
            return {}
        view = {"crmGuestRecordId": row["crm_guest_record_id"], "crmModifiedTime": _iso(row["crm_modified_time"]),
                "normalized": {"firstName": row["canonical_first_name"], "lastName": row["canonical_last_name"],
                               "dob": row["dob_key"].isoformat() if row["dob_key"] else None,
                               "phone": row["phone_e164_key"], "phoneConfidence": row["phone_confidence"],
                               "alternatePhone": row["alt_phone_e164_key"],
                               "email": row["email_key"]},
                "active": row["active_flag"]}
        if show:
            view["display"] = guest_projection.display(self.crypto, row)
        return view

    def _identity_view(self, row, show: bool) -> Optional[dict]:
        if not row:
            return None
        g, l = identity_projection.pair(self.crypto, row)
        view = {"identityId": str(row["identity_id"]), "crmIdentityRecordId": row["crm_identity_record_id"],
                "pairIntegrity": row["pair_integrity"], "lifecycle": row["lifecycle_status"],
                "committed": row["committed"]}
        if show:
            view.update(globalId=g, loyaltyId=l)
        return view

    # ------------------------------------------------------------------ prepare (9.7 steps 1-5)
    def prepare(self, conn: Connection, req: DecisionPreparationRequest, roles: set[str]) -> dict:
        try:
            action = ReviewerAction(req.action)
        except ValueError:
            raise invalid(f"Unknown reviewer action {req.action!r}.")
        if not roles & DECIDE_ROLES:
            raise forbidden()
        if action is ReviewerAction.REVERSE_DECISION and SUPERVISOR not in roles:
            raise forbidden("Reversing a decision requires the Identity Supervisor role.")
        lock(conn, "case:" + req.caseId)
        case = review_cases.get(conn, req.caseId, for_update=True)
        if not case:
            raise not_found("Review case")
        done = review_cases.decision_by_key(conn, req.idempotencyKey)
        if done:
            if done["case_id"] != req.caseId or done["action"] != action.value:
                raise idempotency_conflict()
            return self._prepared_view(done)
        check_review(case["state"], ReviewState.REVIEW_DECISION_PREPARED)

        cands = review_cases.candidates(conn, req.caseId)
        affected = [case["crm_guest_record_id"]] + [c["crm_guest_record_id"] for c in cands]
        shown = {v.crmGuestRecordId: v.crmModifiedTime for v in req.versionsShown}
        current = {gid: guest_projection.get(conn, gid) for gid in affected}
        changed = [gid for gid in affected
                   if gid not in shown or not current[gid] or current[gid]["crm_modified_time"] != shown[gid]]
        if changed:
            metrics.REVIEW_FRESHNESS_FAILURES.inc()
            raise ApiError("REVIEW_DATA_CHANGED", 409, "A Guest changed after the case was displayed; refresh it.",
                           reasonCodes=[str(Reason.REVIEW_VERSION_CHANGED)], changedRecords=changed)

        candidate_ids = {str(c["identity_id"]) for c in cands if c["identity_id"]}
        prov_id = str(case["provisional_identity_id"]) if case["provisional_identity_id"] else None
        selected = None
        if action in (ReviewerAction.CONFIRM_SAME_PERSON, ReviewerAction.REVERSE_DECISION):
            allowed = candidate_ids | ({prov_id} if prov_id and action is ReviewerAction.REVERSE_DECISION else set())
            if not req.selectedIdentityId or req.selectedIdentityId not in allowed:
                raise invalid("selectedIdentityId must be one of the case's candidate identities.")
            selected = identity_projection.get(conn, req.selectedIdentityId)
            if not selected or not selected["committed"] or selected["pair_integrity"] != "COMPLETE" \
                    or selected["lifecycle_status"] not in (IdentityLifecycle.ACTIVE.value, IdentityLifecycle.PROVISIONAL.value):
                raise invalid("The selected identity is not a complete committed identity.")
        elif req.selectedIdentityId:
            raise invalid("selectedIdentityId is only accepted for CONFIRM_SAME_PERSON and REVERSE_DECISION.")
        if action is ReviewerAction.DEFER and (not req.followUpDate or not req.comment):
            raise invalid("DEFER requires a comment and a followUpDate.")
        if action in (ReviewerAction.CONFIRM_DIFFERENT_PEOPLE, ReviewerAction.CONFIRM_HOUSEHOLD) and not prov_id:
            raise invalid("This case has no provisional identity to keep.")

        prov = identity_projection.get(conn, prov_id) if prov_id else None
        target = selected or prov
        patch: dict = {"identityStatus": _STATUS_FOR[action].value, "reviewCaseId": req.caseId,
                       "reviewAction": action.value}
        if action is not ReviewerAction.DEFER and target:
            patch["guestIdentityId"] = target["crm_identity_record_id"]
        if action in (ReviewerAction.CONFIRM_SAME_PERSON, ReviewerAction.REVERSE_DECISION) and prov \
                and prov_id != req.selectedIdentityId:
            patch["aliasIdentityId"] = prov["crm_identity_record_id"]
        if action is ReviewerAction.CONFIRM_HOUSEHOLD:
            patch["householdWith"] = sorted(c["crm_identity_record_id"] for c in cands if c["crm_identity_record_id"])
        if action is ReviewerAction.DEFER:
            patch["followUpDate"] = req.followUpDate.isoformat()
        rd_id = review_cases.new_review_decision_id()
        review_cases.insert_decision(
            conn, review_decision_id=rd_id, case_id=req.caseId, idempotency_key=req.idempotencyKey,
            reviewer_id=req.reviewerId, action=action.value,
            selected_identity_id=req.selectedIdentityId if selected else None, comment=req.comment,
            versions_shown=[{"crmGuestRecordId": g, "crmModifiedTime": _iso(shown[g])} for g in affected],
            crm_records_to_check=[{"crmGuestRecordId": g, "expectedModifiedTime": _iso(current[g]["crm_modified_time"])}
                                  for g in affected],
            crm_patch=patch, state=ReviewState.REVIEW_DECISION_PREPARED.value)
        review_cases.add_event(conn, req.caseId, "DECISION_PREPARED", req.reviewerId,
                               {"reviewDecisionId": rd_id, "action": action.value,
                                "identityStatus": patch["identityStatus"]})
        review_cases.update_case(conn, req.caseId, state=ReviewState.REVIEW_DECISION_PREPARED.value,
                                 assigned_to=req.reviewerId,
                                 follow_up_date=req.followUpDate if action is ReviewerAction.DEFER else case["follow_up_date"])
        return self._prepared_view(review_cases.get_decision(conn, rd_id))

    def _prepared_view(self, rd) -> dict:
        return {"reviewDecisionId": rd["review_decision_id"], "caseId": rd["case_id"], "state": rd["state"],
                "action": rd["action"], "crmRecordsToCheck": rd["crm_records_to_check"],
                "compareFields": COMPARE_FIELDS, "crmPatch": rd["crm_patch"], "errorCode": rd["error_code"]}

    def _locked_decision(self, conn: Connection, rd_id: str):
        rd = review_cases.get_decision(conn, rd_id)
        if not rd:
            raise not_found("Review decision")
        lock(conn, "case:" + rd["case_id"])
        return review_cases.get_decision(conn, rd_id, for_update=True), review_cases.get(conn, rd["case_id"], for_update=True)

    # ------------------------------------------------------------------ freshness failed (9.7 step 7)
    def freshness_failed(self, conn: Connection, rd_id: str, req: FreshnessFailedRequest) -> dict:
        rd, case = self._locked_decision(conn, rd_id)
        if rd["state"] not in (ReviewState.REVIEW_DECISION_PREPARED.value, ReviewState.REVIEW_CRM_UPDATE_PENDING.value):
            raise invalid_state(f"A review decision in state {rd['state']} cannot be cancelled.")
        for ev in req.snapshots:
            row = guest_projection.get(conn, ev.crmGuestRecordId, for_update=True)
            if row and row["crm_modified_time"] > ev.crmModifiedTime:
                continue                                    # never move the projection backwards
            norm = normalize_identity(ev.firstName, ev.lastName, ev.dateOfBirth, ev.phone, ev.email, ev.countryCode,
                                      self.s, citizenship=ev.citizenshipCode, alt_phone=ev.alternatePhone)
            guest_projection.upsert(conn, self.crypto, ev, norm, row["direct_scope_flag"] if row else True)
        metrics.REVIEW_FRESHNESS_FAILURES.inc()
        review_cases.update_decision(conn, rd_id, state=ReviewState.REVIEW_FAILED.value,
                                     error_code=str(Reason.CRM_FRESHNESS_CHECK_FAILED))
        check_review(case["state"], ReviewState.REVIEW_DATA_CHANGED)
        self._reevaluate_case(conn, case)
        review_cases.update_case(conn, case["case_id"], state=ReviewState.REVIEW_DATA_CHANGED.value,
                                 last_result=ReviewState.REVIEW_DATA_CHANGED.value,
                                 reason_codes=list(dict.fromkeys(list(case["reason_codes"]) +
                                                                 [str(Reason.CRM_FRESHNESS_CHECK_FAILED)])))
        review_cases.add_event(conn, case["case_id"], "DATA_CHANGED", None,
                               {"reviewDecisionId": rd_id, "reasonCodes": [str(Reason.CRM_FRESHNESS_CHECK_FAILED)]})
        return {"reviewDecisionId": rd_id, "caseId": case["case_id"], "state": ReviewState.REVIEW_DATA_CHANGED.value,
                "reasonCodes": [str(Reason.CRM_FRESHNESS_CHECK_FAILED)]}

    def _reevaluate_case(self, conn: Connection, case) -> None:
        row = guest_projection.get(conn, case["crm_guest_record_id"])
        if not row:
            return
        norm = guest_projection.normalized_from_row(row)
        exclude = str(case["provisional_identity_id"]) if case["provisional_identity_id"] else None
        cands, exceeded = candidate_retrieval.retrieve(conn, norm, row["crm_guest_record_id"], exclude,
                                                       self.s.candidate_guardrail)
        result = decide(norm, cands, source_code=self.s.direct_source_codes[0],
                        agency_code=self.s.direct_agency_names[0], source_system=row["source_system"],
                        settings=self.s, guardrail_exceeded=exceeded,
                        over_shared_phones=statistics.over_shared_phones(conn, norm.high_phones(), 0, "", refresh_now=False),
                        over_shared_emails={norm.email.key} if statistics.over_shared(conn, "EMAIL", norm.email.key) else set())
        evidence = result.candidates or []
        review_cases.replace_candidates(conn, case["case_id"], [
            {"crm_guest_record_id": e.candidate.crm_guest_record_id, "identity_id": e.candidate.identity_id,
             "crm_identity_record_id": e.candidate.crm_identity_record_id, "field_results": e.fields,
             "reason_codes": [str(r) for r in e.reasons], "shadow": e.shadow} for e in evidence])

    # ------------------------------------------------------------------ commit / fail (9.7 step 8)
    def commit(self, conn: Connection, rd_id: str) -> dict:
        rd, case = self._locked_decision(conn, rd_id)
        if rd["state"] == ReviewState.REVIEW_COMMITTED.value:
            return self._prepared_view(rd)
        if rd["state"] not in (ReviewState.REVIEW_DECISION_PREPARED.value, ReviewState.REVIEW_CRM_UPDATE_PENDING.value):
            raise invalid_state(f"A review decision in state {rd['state']} cannot be committed.")
        action = ReviewerAction(rd["action"])
        guest = case["crm_guest_record_id"]
        prov_id = str(case["provisional_identity_id"]) if case["provisional_identity_id"] else None
        prov = identity_projection.get(conn, prov_id, for_update=True) if prov_id else None
        if action in (ReviewerAction.CONFIRM_SAME_PERSON, ReviewerAction.REVERSE_DECISION):
            sel = identity_projection.get(conn, str(rd["selected_identity_id"]))
            guest_projection.set_identity(conn, guest, str(sel["identity_id"]), sel["crm_identity_record_id"])
            if prov and prov_id != str(sel["identity_id"]):
                identity_projection.set_lifecycle(conn, prov_id, IdentityLifecycle.ALIAS, str(sel["identity_id"]))
        elif action in (ReviewerAction.CONFIRM_DIFFERENT_PEOPLE, ReviewerAction.CONFIRM_HOUSEHOLD):
            if not prov["committed"]:
                raise invalid_state("The provisional identity has not been committed to CRM yet.")
            identity_projection.set_lifecycle(conn, prov_id, IdentityLifecycle.ACTIVE)
        row = guest_projection.get(conn, guest)
        if row:
            statistics.over_shared_phones(conn, {row["phone_e164_key"], row["alt_phone_e164_key"]} - {None},
                                          self.s.over_shared_phone_threshold, self.s.over_shared_threshold_version)
            statistics.refresh(conn, "EMAIL", row["email_key"], self.s.over_shared_email_threshold,
                               self.s.over_shared_threshold_version)
        review_cases.update_decision(conn, rd_id, state=ReviewState.REVIEW_COMMITTED.value, error_code=None)
        case_state = ReviewState.REVIEW_OPEN if action is ReviewerAction.DEFER else ReviewState.REVIEW_COMMITTED
        check_review(case["state"], case_state)
        review_cases.update_case(conn, case["case_id"], state=case_state.value, last_result=action.value)
        review_cases.add_event(conn, case["case_id"], "COMMITTED", rd["reviewer_id"],
                               {"reviewDecisionId": rd_id, "action": action.value, "caseStatus": case_state.value,
                                "reasonCodes": [str(Reason.REVIEW_DECISION_COMMITTED)]})
        return self._prepared_view(review_cases.get_decision(conn, rd_id))

    def fail(self, conn: Connection, rd_id: str, retryable: bool, error_code: str) -> dict:
        rd, case = self._locked_decision(conn, rd_id)
        if rd["state"] == ReviewState.REVIEW_COMMITTED.value:
            raise invalid_state("A committed review decision cannot be failed.")
        if retryable:
            state, case_state = ReviewState.REVIEW_CRM_UPDATE_PENDING, ReviewState.REVIEW_CRM_UPDATE_PENDING
        else:
            state, case_state = ReviewState.REVIEW_FAILED, ReviewState.REVIEW_OPEN   # a new decision may be made
        check_review(case["state"], case_state)
        review_cases.update_decision(conn, rd_id, state=state.value, error_code=error_code)
        review_cases.update_case(conn, case["case_id"], state=case_state.value, last_result=state.value)
        review_cases.add_event(conn, case["case_id"], "CRM_UPDATE_PENDING" if retryable else "FAILED", None,
                               {"reviewDecisionId": rd_id, "errorCode": error_code, "retryable": retryable})
        return self._prepared_view(review_cases.get_decision(conn, rd_id))


    # ------------------------------------------------------------------ Workbench support
    def _comments(self, conn: Connection, case_id: str, show: bool) -> list:
        out = []
        for c in review_cases.comments(conn, case_id):
            item = {"commentId": c["comment_id"], "authorId": c["author_id"], "createdTime": _iso(c["created_time"])}
            if show:
                item["text"] = self.crypto.decrypt(c["text_enc"])
            out.append(item)
        return out

    def list_cases(self, conn: Connection, roles: set, kind=None, status=None, assignee=None,
                   limit: int = 50, offset: int = 0) -> dict:
        if not roles & VIEW_ROLES:
            raise forbidden()
        from datetime import datetime, timezone
        rows, total = review_cases.queue(conn, kind, status, assignee, limit, offset)
        t = datetime.now(timezone.utc)
        cases = [{"caseId": r["case_id"], "kind": r["kind"], "priority": r["priority"], "caseStatus": r["state"],
                  "assignedTo": r["assigned_to"], "crmGuestRecordId": r["crm_guest_record_id"],
                  "candidateCount": r["candidate_count"], "createdTime": _iso(r["created_time"]),
                  "ageHours": round((t - r["created_time"]).total_seconds() / 3600, 1),
                  "slaDueTime": _iso(r["sla_due_time"]),
                  "overdue": bool(r["sla_due_time"] and r["sla_due_time"] < t),
                  "followUpDate": r["follow_up_date"].isoformat() if r["follow_up_date"] else None}
                 for r in rows]
        return {"cases": cases, "total": total, "limit": limit, "offset": offset}

    def history(self, conn: Connection, case_id: str, roles: set) -> dict:
        if not roles & VIEW_ROLES:
            raise forbidden()
        if not review_cases.get(conn, case_id):
            raise not_found("Review case")
        return {"caseId": case_id, "history": [
            {"eventId": e["event_id"], "type": e["event_type"], "actorId": e["actor_id"],
             "time": _iso(e["created_time"]), "details": e["details"]} for e in review_cases.history(conn, case_id)]}

    def assign(self, conn: Connection, case_id: str, assignee_id: str, assigned_by: str, roles: set) -> dict:
        if not roles & DECIDE_ROLES:
            raise forbidden()
        if assignee_id != assigned_by and SUPERVISOR not in roles:
            raise forbidden("Handing a case to someone else requires the Identity Supervisor role.")
        lock(conn, "case:" + case_id)
        case = review_cases.get(conn, case_id, for_update=True)
        if not case:
            raise not_found("Review case")
        if case["state"] == ReviewState.REVIEW_COMMITTED.value:
            raise invalid_state("A closed case cannot be assigned.")
        review_cases.update_case(conn, case_id, assigned_to=assignee_id)
        review_cases.add_event(conn, case_id, "ASSIGNED", assigned_by,
                               {"from": case["assigned_to"], "to": assignee_id,
                                "handover": assignee_id != assigned_by})
        return {"caseId": case_id, "assignedTo": assignee_id, "assignedBy": assigned_by}

    def comment(self, conn: Connection, case_id: str, author_id: str, text: str, roles: set) -> dict:
        if not roles & COMMENT_ROLES:
            raise forbidden()
        if not review_cases.get(conn, case_id):
            raise not_found("Review case")
        import uuid as _uuid
        cid = "CM-" + _uuid.uuid4().hex[:16].upper()
        review_cases.add_comment(conn, cid, case_id, author_id, self.crypto.encrypt(text))
        review_cases.add_event(conn, case_id, "COMMENTED", author_id, {"commentId": cid, "length": len(text)})
        return {"commentId": cid, "caseId": case_id, "authorId": author_id}
