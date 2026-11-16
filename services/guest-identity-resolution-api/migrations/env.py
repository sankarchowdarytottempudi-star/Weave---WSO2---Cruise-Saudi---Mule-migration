"""Alembic environment. The database URL comes from the GIR_DATABASE_URL secret (file or env)."""
from alembic import context
from sqlalchemy import text

from app.config import database_url, get_settings
from app.db.session import make_engine


def run_migrations_online() -> None:
    settings = get_settings()
    url = context.config.attributes.get("url") or database_url(settings)
    schema = context.config.attributes.get("schema") or settings.database_schema
    app_role = context.config.attributes.get("app_role", settings.app_db_role)
    engine = make_engine(url, schema)
    with engine.connect() as connection:
        connection.execute(text(f'CREATE SCHEMA IF NOT EXISTS "{schema}"'))
        connection.commit()
        context.configure(connection=connection, version_table_schema=schema)
        with context.begin_transaction():
            context.run_migrations()
        if app_role:
            grant_app_role(connection, schema, app_role)
            connection.commit()


def grant_app_role(connection, schema: str, role: str) -> None:
    """Least privilege: the migration owner owns the objects; the runtime role gets DML only
    (no DDL, no TRUNCATE, no ownership). Idempotent; re-run by every migration Job."""
    for name in (schema, role):
        if not name.replace("_", "").replace("-", "").isalnum():
            raise RuntimeError("schema/role names must be alphanumeric, '_' or '-'")
    q = lambda n: '"' + n + '"'
    for stmt in (f"GRANT USAGE ON SCHEMA {q(schema)} TO {q(role)}",
                 f"GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA {q(schema)} TO {q(role)}",
                 f"GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA {q(schema)} TO {q(role)}",
                 f"REVOKE ALL ON {q(schema)}.alembic_version FROM {q(role)}",
                 f"GRANT SELECT ON {q(schema)}.alembic_version TO {q(role)}"):
        connection.execute(text(stmt))


run_migrations_online()
