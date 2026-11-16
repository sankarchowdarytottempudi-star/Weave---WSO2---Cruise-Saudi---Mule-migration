"""PostgreSQL smoke test for the Guest Identity Resolution decision service (runs inside its image).

Read-only on the database except for a migration dry-run that runs every pending Alembic migration
inside ONE transaction and rolls it back (PostgreSQL DDL is transactional), so nothing is left behind.
Prints yes/no answers and versions only: never the host, database, user, password or any row.
"""
import os
import sys

sys.path.insert(0, os.environ.get("GIR_APP_DIR", os.getcwd()))   # the image's working directory holds app/

from alembic.config import Config
from alembic.operations import Operations
from alembic.runtime.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import text

from app.config import database_url, get_settings
from app.db.session import make_engine

failures = 0


def line(what, ok, detail=""):
    global failures
    failures += 0 if ok else 1
    print(f"SMOKE postgres {what}: {'OK' if ok else 'FAILED'}" + (f" - {detail}" if detail else ""), flush=True)


def main() -> int:
    s = get_settings()
    schema = s.database_schema
    try:
        engine = make_engine(database_url(s), schema)
        conn = engine.connect()
    except Exception as e:                      # noqa: BLE001 - report the kind only
        line("connect (network, TLS, authentication)", False, type(e).__name__)
        return 1
    with conn:
        line("connect (network, TLS, authentication)", True)
        ssl = conn.execute(text("SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid()")).first()
        line("connection encrypted", bool(ssl and ssl[0]), (ssl[1] or "") if ssl else "no pg_stat_ssl row")
        line("server version", True, str(conn.execute(text("SHOW server_version")).scalar()))
        can_create = conn.execute(text("SELECT has_database_privilege(current_user, current_database(), 'CREATE')")).scalar()
        exists = conn.execute(text("SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = :s)"), {"s": schema}).scalar()
        line("schema present or creatable by the migration role", bool(exists or can_create),
             "present" if exists else ("will be created" if can_create else "missing and no CREATE privilege"))
        script = ScriptDirectory.from_config(Config("alembic.ini"))
        heads = tuple(script.get_heads())
        current = ()
        if exists:
            has_version = conn.execute(text("SELECT to_regclass(:t) IS NOT NULL"), {"t": f'"{schema}".alembic_version'}).scalar()
            if has_version:
                current = tuple(r[0] for r in conn.execute(text(f'SELECT version_num FROM "{schema}".alembic_version')))
        line("migration state", True, f"current {list(current) or 'none'} -> target {list(heads)}")
        conn.commit()
        tx = conn.begin()
        try:
            conn.execute(text(f'CREATE SCHEMA IF NOT EXISTS "{schema}"'))
            conn.execute(text(f'SET LOCAL search_path TO "{schema}"'))
            ctx = MigrationContext.configure(conn, opts={
                "version_table_schema": schema, "script": script,
                "fn": lambda rev, _ctx: script._upgrade_revs("heads", rev)})
            with Operations.context(ctx):
                ctx.run_migrations()
            line("migration dry-run (applied in a transaction, then rolled back)", True,
                 f"would reach {list(ctx.get_current_heads())}")
        except Exception as e:                  # noqa: BLE001
            line("migration dry-run (applied in a transaction, then rolled back)", False, type(e).__name__ + ": "
                 + str(e).split("\n")[0][:160])
        finally:
            tx.rollback()
    app_password_file = os.environ.get("GIR_APP_DB_PASSWORD_FILE", "")
    if app_password_file and os.environ.get("GIR_APP_DB_USER"):
        os.environ["GIR_DB_USER"] = os.environ["GIR_APP_DB_USER"]
        os.environ["GIR_DB_PASSWORD_FILE"] = app_password_file
        get_settings.cache_clear() if hasattr(get_settings, "cache_clear") else None
        try:
            with make_engine(database_url(get_settings()), schema).connect() as c2:
                c2.execute(text("SELECT 1"))
            line("runtime role connects", True)
        except Exception as e:                  # noqa: BLE001
            line("runtime role connects", False, type(e).__name__)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
