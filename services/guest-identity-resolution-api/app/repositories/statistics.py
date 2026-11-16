"""Identifier sharing statistics (12.3, 17.1): distinct ACTIVE identities per phone/email key, and
per suspicious DOB (e.g. 1970-01-01, which is a placeholder only when over-shared)."""
from __future__ import annotations

from typing import Optional

from sqlalchemy import func, or_, select, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.engine import Connection

from app.db.models import guest_match_index as g, identifier_statistics as s
from app.repositories.guest_projection import now


_COLUMNS = {"PHONE": g.c.phone_e164_key, "EMAIL": g.c.email_key, "DOB": g.c.dob_key}


def refresh(conn: Connection, key_type: str, key_value, threshold: int, version: str) -> bool:
    if not key_value:
        return False
    match = (or_(g.c.phone_e164_key == key_value, g.c.alt_phone_e164_key == key_value) if key_type == "PHONE"
             else _COLUMNS[key_type] == key_value)
    count = conn.execute(select(func.count(func.distinct(g.c.identity_id)))
                         .where(g.c.active_flag.is_(True), match, g.c.identity_id.is_not(None))).scalar_one()
    key_value = str(key_value)
    over = count > threshold
    stmt = insert(s).values(key_type=key_type, key_value=key_value, distinct_identity_count=count, over_shared=over,
                            threshold_version=version, updated_time=now())
    conn.execute(stmt.on_conflict_do_update(index_elements=[s.c.key_type, s.c.key_value], set_=dict(
        distinct_identity_count=count, over_shared=over, threshold_version=version, updated_time=now())))
    return over


def over_shared(conn: Connection, key_type: str, key_value: Optional[str]) -> bool:
    if not key_value:
        return False
    row = conn.execute(select(s.c.over_shared).where(s.c.key_type == key_type, s.c.key_value == key_value)).first()
    return bool(row and row[0])


def over_shared_phones(conn: Connection, phones, threshold: int, version: str, refresh_now: bool = True) -> set:
    """The subset of the given E.164 keys that is over-shared (refreshing the counts first)."""
    if refresh_now:
        return {p for p in phones if refresh(conn, "PHONE", p, threshold, version)}
    return {p for p in phones if over_shared(conn, "PHONE", p)}


def refresh_many(conn: Connection, key_type: str, keys, threshold: int, version: str) -> None:
    """Set-based refresh of many keys in one statement (bootstrap)."""
    keys = sorted(k for k in keys if k)
    if not keys:
        return
    if key_type == "PHONE":
        src = """SELECT phone_e164_key AS k, identity_id FROM guest_match_index
                   WHERE active_flag AND identity_id IS NOT NULL AND phone_e164_key = ANY(:keys)
                 UNION ALL
                 SELECT alt_phone_e164_key, identity_id FROM guest_match_index
                   WHERE active_flag AND identity_id IS NOT NULL AND alt_phone_e164_key = ANY(:keys)"""
    else:
        src = """SELECT email_key AS k, identity_id FROM guest_match_index
                   WHERE active_flag AND identity_id IS NOT NULL AND email_key = ANY(:keys)"""
    conn.execute(text(f"""
        INSERT INTO identifier_statistics (key_type, key_value, distinct_identity_count, over_shared, threshold_version, updated_time)
        SELECT :kt, u.k, coalesce(c.n, 0), coalesce(c.n, 0) > :th, :v, now()
          FROM unnest(CAST(:keys AS varchar[])) AS u(k)
          LEFT JOIN (SELECT k, count(DISTINCT identity_id) AS n FROM ({src}) s GROUP BY k) c ON c.k = u.k
        ON CONFLICT (key_type, key_value) DO UPDATE SET distinct_identity_count = EXCLUDED.distinct_identity_count,
          over_shared = EXCLUDED.over_shared, threshold_version = EXCLUDED.threshold_version, updated_time = now()"""),
        {"kt": key_type, "keys": keys, "th": threshold, "v": version})
