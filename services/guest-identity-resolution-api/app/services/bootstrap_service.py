"""Index bootstrap (plan section 16): load CRM snapshots into the projection, mark only complete
conflict-free pairs reusable (16.1/16.2), and run the Phase 1 rules in DRY-RUN mode for counts.
Never allocates pairs, never opens cases, never touches CRM."""
from __future__ import annotations

import hashlib
import json
import time
from collections import Counter
from typing import Optional

import uuid

from sqlalchemy import func, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.engine import Connection

from app.config import Settings
from app.db.crypto import Crypto
from app.db.models import bootstrap_batch as bb, guest_match_index as g, identity_projection as ip
from app.db.session import lock
from app.domain.errors import idempotency_conflict
from app.domain.enums import IdentityLifecycle, PairIntegrity
from app.repositories import guest_projection, statistics
from app.services.pair_allocator import is_reusable_pair
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
        """Set-based: a handful of statements per batch (not per record). Batches are serialized by
        an advisory lock so identity creation never races between concurrent batches."""
        started = time.monotonic()
        h = hashlib.sha256(json.dumps(batch.model_dump(mode="json"), sort_keys=True).encode()).hexdigest()
        lock(conn, "bootstrap")
        done = conn.execute(select(bb).where(bb.c.batch_id == batch.batchId)).mappings().first()
        if done:
            if done["payload_hash"] != h:
                raise idempotency_conflict()
            return {"batchId": batch.batchId, "replayed": True, "received": done["received"], **done["counts"]}
        counts: Counter = Counter()
        # last snapshot wins inside one batch
        recs = {}
        for rec in batch.records:
            prev = recs.get(rec.crmGuestRecordId)
            if prev is None or rec.crmModifiedTime >= prev.crmModifiedTime:
                recs[rec.crmGuestRecordId] = rec
        counts["duplicateInBatch"] = len(batch.records) - len(recs)
        ids = list(recs)
        current = {r["crm_guest_record_id"]: r for r in conn.execute(
            select(g.c.crm_guest_record_id, g.c.crm_modified_time, g.c.identity_id, g.c.crm_identity_record_id)
            .where(g.c.crm_guest_record_id.in_(ids))).mappings()}
        fresh = []
        for gid, rec in recs.items():
            cur = current.get(gid)
            if cur and cur["crm_modified_time"] > rec.crmModifiedTime:
                counts["staleSkipped"] += 1
            else:
                fresh.append(rec)
        identity_of = self._resolve_identities(conn, fresh, counts)
        rows, phones, emails = [], set(), set()
        for rec in fresh:
            norm = normalize_identity(rec.firstName, rec.lastName, rec.dateOfBirth, rec.phone, rec.email,
                                      rec.countryCode, self.s, citizenship=rec.citizenshipCode, alt_phone=rec.alternatePhone)
            direct = is_direct(rec.sourceCode, rec.agencyName or rec.agencyCode, rec.sourceSystem, self.s)
            counts["directScope" if direct else "excludedNonDirect"] += 1
            if not rec.active:
                counts["inactive"] += 1
            cur = current.get(rec.crmGuestRecordId)
            ident, crm_ident = identity_of.get(rec.crmGuestRecordId) or (
                (cur["identity_id"], cur["crm_identity_record_id"]) if cur else (None, None))
            counts["linkedToIdentity" if ident else "pendingIdentity"] += 1
            rows.append(guest_projection.row_values(self.crypto, _Snapshot(rec), norm, direct, ident, crm_ident))
            phones |= norm.high_phones()
            if norm.email.key:
                emails.add(norm.email.key)
        for i in range(0, len(rows), 1000):
            guest_projection.upsert_many(conn, rows[i:i + 1000])
        counts["indexed"] = len(rows)
        statistics.refresh_many(conn, "PHONE", phones, self.s.over_shared_phone_threshold, self.s.over_shared_threshold_version)
        statistics.refresh_many(conn, "EMAIL", emails, self.s.over_shared_email_threshold, self.s.over_shared_threshold_version)
        result = {k: v for k, v in sorted(counts.items()) if v}
        ms = int((time.monotonic() - started) * 1000)
        conn.execute(bb.insert().values(batch_id=batch.batchId, payload_hash=h, received=len(batch.records),
                                        counts=result, duration_ms=ms, created_time=now()))
        return {"batchId": batch.batchId, "replayed": False, "received": len(batch.records), "durationMs": ms, **result}

    def _resolve_identities(self, conn: Connection, recs: list, counts: Counter) -> dict:
        """Existing CRM pairs -> identity_projection rows, keyed by the CRM identity (or Global ID).
        Only complete, conflict-free pairs stay COMPLETE (16.1); one ID under two pairs -> both CONFLICT."""
        wanted = {}
        for rec in recs:
            if rec.currentIdentityId or rec.currentGlobalId or rec.currentLoyaltyId:
                key = rec.currentIdentityId or ("GID:" + rec.currentGlobalId if rec.currentGlobalId
                                                else "LID:" + rec.currentLoyaltyId)
                wanted.setdefault(key, []).append(rec)
        if not wanted:
            return {}
        existing = {r["crm_identity_record_id"]: dict(r) for r in conn.execute(
            select(ip.c.identity_id, ip.c.crm_identity_record_id, ip.c.global_id_hash, ip.c.loyalty_id_hash,
                   ip.c.pair_integrity).where(ip.c.crm_identity_record_id.in_(list(wanted)))).mappings()}
        h = self.crypto.keyed_hash
        all_hashes = {x for rs in wanted.values() for r in rs for x in (h(r.currentGlobalId), h(r.currentLoyaltyId)) if x}
        owner = {}
        if all_hashes:
            for r in conn.execute(select(ip.c.identity_id, ip.c.global_id_hash, ip.c.loyalty_id_hash)
                                  .where((ip.c.global_id_hash.in_(all_hashes)) | (ip.c.loyalty_id_hash.in_(all_hashes)))).mappings():
                for col in ("global_id_hash", "loyalty_id_hash"):
                    if r[col]:
                        owner[r[col]] = str(r["identity_id"])
        conflicts, inserts, out = set(), [], {}
        t = now()
        for key, rs in wanted.items():
            first = rs[0]
            g_vals = {r.currentGlobalId for r in rs if r.currentGlobalId}
            l_vals = {r.currentLoyaltyId for r in rs if r.currentLoyaltyId}
            if key in existing:
                ident = str(existing[key]["identity_id"])
                e = existing[key]
                if (e["global_id_hash"] and any(h(v) != e["global_id_hash"] for v in g_vals)) or \
                   (e["loyalty_id_hash"] and any(h(v) != e["loyalty_id_hash"] for v in l_vals)):
                    conflicts.add(ident)
            else:
                ident = str(uuid.uuid4())
                gid = sorted(g_vals)[0] if g_vals else None
                lid = sorted(l_vals)[0] if l_vals else None
                integrity = PairIntegrity.COMPLETE if is_reusable_pair(gid, lid) else PairIntegrity.INCOMPLETE
                gh, lh = h(gid), h(lid)
                if len(g_vals) > 1 or len(l_vals) > 1:
                    integrity = PairIntegrity.CONFLICT
                for x in (gh, lh):
                    if x and x in owner and owner[x] != ident:
                        conflicts.add(owner[x])
                        integrity = PairIntegrity.CONFLICT
                if integrity is PairIntegrity.CONFLICT:
                    gh = lh = None
                else:
                    for x in (gh, lh):
                        if x:
                            owner[x] = ident
                inserts.append(dict(identity_id=ident, crm_identity_record_id=key, global_id_enc=self.crypto.encrypt(gid),
                                    loyalty_id_enc=self.crypto.encrypt(lid), global_id_hash=gh, loyalty_id_hash=lh,
                                    pair_integrity=integrity.value, lifecycle_status=IdentityLifecycle.ACTIVE.value,
                                    committed=True, created_by_process="BASELINE", rule_version=self.s.active_rule_version,
                                    created_time=t, modified_time=t))
            for r in rs:
                out[r.crmGuestRecordId] = (ident, key)
        for i in range(0, len(inserts), 1000):
            conn.execute(ip.insert(), inserts[i:i + 1000])
        if conflicts:
            conn.execute(update(ip).where(ip.c.identity_id.in_(list(conflicts)))
                         .values(pair_integrity=PairIntegrity.CONFLICT.value, modified_time=t))
        counts["identitiesCreated"] += len(inserts)
        counts["identitiesMarkedConflict"] += len(conflicts)
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
