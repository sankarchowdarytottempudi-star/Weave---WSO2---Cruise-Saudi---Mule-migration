"""Database engine and short transactions (section 9.8: never hold a transaction while CRM is called;
Python never calls CRM at all)."""
from __future__ import annotations

from contextlib import contextmanager
from functools import lru_cache

from sqlalchemy import create_engine
from sqlalchemy.engine import Connection, Engine

from app.config import database_url, get_settings


def make_engine(url, schema: str = "gir", **kw) -> Engine:
    """All objects live in a dedicated schema of the (existing, customer-provided) database."""
    if not schema.replace("_", "").isalnum():
        raise RuntimeError("GIR_DATABASE_SCHEMA must be alphanumeric/underscore")
    return create_engine(url, pool_pre_ping=True, connect_args={"options": f"-csearch_path={schema}"}, **kw)


@lru_cache(maxsize=1)
def get_engine() -> Engine:
    s = get_settings()
    return make_engine(database_url(s), s.database_schema, pool_size=s.db_pool_size, max_overflow=s.db_max_overflow)


@contextmanager
def transaction(engine: Engine | None = None):
    with (engine or get_engine()).begin() as conn:  # commits on success, rolls back on error
        yield conn


def lock(conn: Connection, *keys: str) -> None:
    """Transaction-scoped advisory locks, always taken in sorted order to avoid deadlocks."""
    from sqlalchemy import text
    for k in sorted(set(k for k in keys if k)):
        conn.execute(text("SELECT pg_advisory_xact_lock(hashtextextended(:k, 0))"), {"k": k})
