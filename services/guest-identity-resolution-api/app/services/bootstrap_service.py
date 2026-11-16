"""Index bootstrap (plan section 16): load CRM snapshots into the projection, mark only complete
conflict-free pairs reusable (16.1/16.2), and run the Phase 1 rules in DRY-RUN mode for counts.
Never allocates pairs, never opens cases, never touches CRM."""
from __future__ import annotations

import hashlib
import json
import time
from collections import Counter
from typing import Optional

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.engine import Connection

from app.config import Settings
from app.db.crypto import Crypto
from app.db.models import bootstrap_batch as bb, guest_match_index as g, identity_projection as ip
from app.db.session import lock
from app.domain.errors import idempotency_conflict
from app.repositories import guest_projection, identity_projection, statistics
from app.repositories.guest_projection import now
from app.schemas.bootstrap import BootstrapBatch, BootstrapRecord, DryRunRequest
from app.services import candidate_retrieval
from app.services.normalization import normalize_identity
from app.services.rule_engine import decide, is_direct


class BootstrapService:
    def __init__(self, settings: Settings, crypto: Crypto):
        self.s, self.crypto = settings, crypto

    # ------------------------------------------------------------------ load
    def load(self, conn: Connection, batch: BootstrapBatch) -> dict:
        started = time.monotonic()
        h = hashlib.sha256(json.dumps(batch.model_dump(mode="json"), sort_keys=True).encode()).hexdigest()
        lock(conn, "bootstrap:" + batch.batchId)
        done = conn.execute(select(bb).where(bb.c.batch_id == batch.batchId)).mappings().first()
        if done:
            if done["payload_hash"] != h:
                raise idempotency_conflict()
            return {"batchId": batch.batchId, "replayed": True, "received": done["received"], **done["counts"]}
        counts: Counter = Counter()
        phones, emails = set(), set()
        for rec in batch.records:
            outcome = self._load_one(conn, rec, phones, emails)
            for k in outcome:
                counts[k] += 1
        for key in phones:
            statistics.refresh(conn, "PHONE", key, self.s.over_shared_phone_threshold, self.s.over_shared_threshold_version)
        for key in emails:
            statistics.refresh(conn, "EMAIL", key, self.s.over_shared_email_threshold, self.s.over_shared_threshold_version)
        result = dict(sorted(counts.items()))
        ms = int((time.monotonic() - started) * 1000)
        conn.execute(bb.insert().values(batch_id=batch.batchId, payload_hash=h, received=len(batch.records),
                                        counts=result, duration_ms=ms, created_time=now()))
        return {"batchId": batch.batchId, "replayed": False, "received": len(batch.records), "durationMs": ms, **result}

    def _load_one(self, conn: Connection, rec: BootstrapRecord, phones: set, emails: set) -> list[str]:
        out = []
        current = guest_projection.get(conn, rec.crmGuestRecordId, for_update=True)
        if current and current["crm_modified_time"] > rec.crmModifiedTime:
            return ["staleSkipped"]
        norm = normalize_identity(rec.firstName, rec.lastName, rec.dateOfBirth, rec.phone, rec.email,
                                  rec.countryCode, self.s, citizenship=rec.citizenshipCode, alt_phone=rec.alternatePhone)
        direct = is_direct(rec.sourceCode, rec.agencyName or rec.agencyCode, rec.sourceSystem, self.s)
        out.append("directScope" if direct else "excludedNonDirect")
        if not rec.active:
            out.append("inactive")
        identity_id, crm_identity = (current["identity_id"], current["crm_identity_record_id"]) if current else (None, None)
        if rec.currentIdentityId or rec.currentGlobalId or rec.currentLoyaltyId:
            crm_identity = rec.currentIdentityId or ("GID:" + rec.currentGlobalId if rec.currentGlobalId
                                                     else "LID:" + rec.currentLoyaltyId)
            identity_id = identity_projection.ensure_external(conn, self.crypto, crm_identity, rec.currentGlobalId,
                                                              rec.currentLoyaltyId, self.s.active_rule_version)
            out.append("linkedToIdentity")
        else:
            out.append("pendingIdentity")
        ev = _Snapshot(rec)
        guest_projection.upsert(conn, self.crypto, ev, norm, direct, identity_id=identity_id,
                                crm_identity_record_id=crm_identity if identity_id else None)
        out.append("indexed")
        phones |= norm.high_phones()
        if norm.email.key:
            emails.add(norm.email.key)
        return out

    # ------------------------------------------------------------------ status
    def status(self, conn: Connection) -> dict:
        guests = dict(conn.execute(select(g.c.direct_scope_flag, func.count()).group_by(g.c.direct_scope_flag)).all())
        linked = conn.execute(select(func.count()).where(g.c.identity_id.is_not(None))).scalar_one()
        integrity = dict(conn.execute(select(ip.c.pair_integrity, func.count()).group_by(ip.c.pair_integrity)).all())
        lifecycle = dict(conn.execute(select(ip.c.lifecycle_status, func.count()).group_by(ip.c.lifecycle_status)).all())
        batches = conn.execute(select(func.count(), func.coalesce(func.sum(bb.c.received), 0),
                                      func.max(bb.c.created_time))).one()
        return {"guests": {"total": sum(guests.values()), "directScope": guests.get(True, 0),
                           "excludedNonDirect": guests.get(False, 0), "linkedToIdentity": linked},
                "identities": {"byPairIntegrity": integrity, "byLifecycle": lifecycle},
                "batches": {"count": batches[0], "recordsReceived": int(batches[1]),
                            "lastLoaded": batches[2].isoformat() if batches[2] else None}}

    # ------------------------------------------------------------------ dry run (16.1)
    def dry_run(self, conn: Connection, req: DryRunRequest) -> dict:
        """Phase 1 rules over indexed direct Guests, without allocating, linking or writing."""
        q = select(g).where(g.c.active_flag.is_(True), g.c.direct_scope_flag.is_(True))
        if req.afterGuestId:
            q = q.where(g.c.crm_guest_record_id > req.afterGuestId)
        if req.onlyWithoutIdentity:
            q = q.where(g.c.identity_id.is_(None))
        rows = conn.execute(q.order_by(g.c.crm_guest_record_id).limit(req.limit)).mappings().all()
        outcomes, candidates_hist = Counter(), Counter()
        started = time.monotonic()
        for row in rows:
            norm = guest_projection.normalized_from_row(row)
            cands, exceeded = candidate_retrieval.retrieve(conn, norm, row["crm_guest_record_id"],
                                                           str(row["identity_id"]) if row["identity_id"] else None,
                                                           self.s.candidate_guardrail)
            candidates_hist[_bucket(len(cands))] += 1
            r = decide(norm, cands, source_code=self.s.direct_source_codes[0],
                       agency_code=self.s.direct_agency_names[0], source_system=row["source_system"], settings=self.s,
                       guardrail_exceeded=exceeded,
                       over_shared_phones=statistics.over_shared_phones(conn, norm.high_phones(), 0, "", refresh_now=False),
                       over_shared_emails={norm.email.key} if statistics.over_shared(conn, "EMAIL", norm.email.key) else set())
            key = r.decision_type.value
            if row["identity_id"] and r.decision.value == "REUSE_EXISTING_IDENTITY":
                key = "ALREADY_LINKED_SAME_PERSON_OTHER_IDENTITY"       # would be a re-evaluation conflict
            outcomes[key] += 1
        nxt: Optional[str] = rows[-1]["crm_guest_record_id"] if len(rows) == req.limit else None
        return {"evaluated": len(rows), "outcomes": dict(sorted(outcomes.items())),
                "candidateCounts": dict(sorted(candidates_hist.items())), "nextAfterGuestId": nxt,
                "durationMs": int((time.monotonic() - started) * 1000), "dryRun": True}


def _bucket(n: int) -> str:
    return "0" if n == 0 else "1" if n == 1 else "2-5" if n <= 5 else "6-25" if n <= 25 else "26-100" if n <= 100 else ">100"


class _Snapshot:
    """Adapts a BootstrapRecord to the attributes guest_projection.upsert reads."""
    def __init__(self, rec: BootstrapRecord):
        self.crmGuestRecordId, self.sourceSystem = rec.crmGuestRecordId, rec.sourceSystem
        self.sourceRecordId = rec.sourceRecordId or rec.crmGuestRecordId
        self.firstName, self.lastName, self.dateOfBirth = rec.firstName, rec.lastName, rec.dateOfBirth
        self.phone, self.email, self.active, self.crmModifiedTime = rec.phone, rec.email, rec.active, rec.crmModifiedTime
        self.alternatePhone = rec.alternatePhone
