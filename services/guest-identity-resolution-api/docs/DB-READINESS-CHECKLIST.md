# Customer PostgreSQL (Tencent) readiness checklist

This is what the customer DBA creates before the first migration. Nothing here contains a secret.
Send credentials through a secure channel; they go straight into Kubernetes Secrets, never into chat or git.

## 1. Server
- PostgreSQL **16** (14+ works; 16 is what CI runs). TLS on, with a certificate the CA bundle can verify (`sslmode=verify-full`, matching host name).
- Network: allow TCP 5432 **only** from the integration cluster's egress address(es). Give us the DB's private CIDR for the NetworkPolicy (`database.egressCidr`).
- Time zone UTC (`timezone = 'UTC'`). The app stores `timestamptz` either way.

## 2. Database, schema and roles (least privilege)
```sql
CREATE DATABASE gir ENCODING 'UTF8' LC_COLLATE 'C.UTF-8' LC_CTYPE 'C.UTF-8' TEMPLATE template0;
\c gir
-- schema owner: used ONLY by the migration Job (DDL)
CREATE ROLE gir_owner LOGIN PASSWORD '<generated>' CONNECTION LIMIT 3;
-- runtime role: used by the API pods (DML only)
CREATE ROLE gir_app   LOGIN PASSWORD '<generated>' CONNECTION LIMIT 30;
REVOKE ALL ON DATABASE gir FROM PUBLIC;
GRANT CONNECT ON DATABASE gir TO gir_owner, gir_app;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA gir AUTHORIZATION gir_owner;
GRANT USAGE ON SCHEMA gir TO gir_app;
ALTER ROLE gir_app   SET search_path = gir;
ALTER ROLE gir_owner SET search_path = gir;
ALTER ROLE gir_app   SET statement_timeout = '15s';
ALTER ROLE gir_app   SET idle_in_transaction_session_timeout = '30s';
```
Each migration Job (`alembic upgrade head` as `gir_owner`, with `GIR_APP_DB_ROLE=gir_app`) re-grants
`SELECT, INSERT, UPDATE, DELETE` on all tables and `USAGE, SELECT` on sequences to `gir_app`.
`gir_app` gets no DDL, no TRUNCATE and owns nothing. Neither role is a superuser or has `CREATEROLE` or `CREATEDB`.

## 3. Extensions
- **None required.** The rules use exact indexed blocks only. Advisory locks and `hashtextextended` are built in.
  `gen_random_uuid()` is core in PostgreSQL 13+.
- `pg_trgm`: **optional and not used in Phase 1.** It is only needed if fuzzy search is approved later (weighted model, D11).
- `pg_stat_statements`: recommended for the DBA's own monitoring.

## 4. Connection limits
- API: 2 replicas × (pool 5 + overflow 5) = **20** max. Migration Job: 1. Allow 30 for `gir_app` so rolling updates have headroom.
- PgBouncer is optional. If used, choose session or transaction pooling (`pg_advisory_xact_lock` works in both) and never statement pooling.

## 5. Sizing (500,000 guests, measured on the interim instance)
- See the interim instance's measured size in TESTING.md. Plan for **~2–3 GB** of data plus indexes at 500k guests with decisions and audit, and provision **20 GB** to leave room for growth, WAL and vacuum.
- Suggested parameters (2 vCPU / 4 GB): `shared_buffers=1GB`, `effective_cache_size=3GB`, `work_mem=16MB`,
  `maintenance_work_mem=256MB`, `max_wal_size=2GB`, `random_page_cost=1.1` (SSD), and autovacuum defaults with
  `autovacuum_vacuum_scale_factor=0.05` on `guest_match_index`.

## 6. Backup and recovery (expectations)
- Daily full backup plus continuous WAL archiving (point-in-time recovery), target **RPO ≤ 15 min, RTO ≤ 4 h**.
- Retention: 7 daily + 4 weekly, **encrypted at rest**. Restores are tested at least once before go-live.
- The schema can always be rebuilt with `alembic upgrade head` plus a re-run of the baseline bootstrap.
  Decisions and audit rows **cannot** be rebuilt and are what the backup protects (5-year retention, ASSUMPTION/PDPL).

## 7. What we need back (non-secret unless marked)
| item | example |
|---|---|
| host name (private) | `postgres-xxxx.tencentcdb.com` |
| port | 5432 |
| database / schema | `gir` / `gir` |
| CA bundle (PEM) | file, into Secret `gir-db-ca` |
| private CIDR | `10.x.x.x/24` |
| `gir_owner` password | **secret**, into Secret `gir-db-owner` |
| `gir_app` password | **secret**, into Secret `gir-db-app` |
