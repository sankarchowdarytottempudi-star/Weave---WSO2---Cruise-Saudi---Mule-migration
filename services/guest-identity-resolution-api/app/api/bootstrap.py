"""Bootstrap API (plan 16): POST /v1/bootstrap/batches (JSON or NDJSON, <= 5,000 records),
GET /v1/bootstrap/status, POST /v1/bootstrap/dry-run. Idempotent per batchId; no CRM."""
from __future__ import annotations

import json

from fastapi import APIRouter, Depends, Request
from pydantic import ValidationError

from app.api.deps import Container, container, require_service
from app.domain.errors import ApiError, invalid
from app.schemas.bootstrap import MAX_BATCH, BootstrapBatch, DryRunRequest

router = APIRouter(prefix="/v1/bootstrap", dependencies=[Depends(require_service)], tags=["bootstrap"])
MAX_BODY = 25 * 1024 * 1024


@router.post("/batches")
async def load_batch(request: Request, c: Container = Depends(container)):
    body = await request.body()
    if len(body) > MAX_BODY:
        raise ApiError("PAYLOAD_TOO_LARGE", 413, f"A batch body may not exceed {MAX_BODY // 1048576} MB.")
    try:
        if request.headers.get("content-type", "").startswith("application/x-ndjson"):
            batch_id = request.query_params.get("batchId")
            records = [json.loads(line) for line in body.splitlines() if line.strip()]
            batch = BootstrapBatch(batchId=batch_id or "", records=records)
        else:
            batch = BootstrapBatch(**json.loads(body or b"{}"))
    except (ValueError, ValidationError) as exc:
        fields = []
        if isinstance(exc, ValidationError):
            fields = [{"field": ".".join(str(p) for p in e["loc"]), "problem": e["type"]} for e in exc.errors()][:50]
        raise ApiError("INVALID_REQUEST", 422, f"The batch is not valid (max {MAX_BATCH} records).", fields=fields)
    with c.engine.begin() as conn:
        return c.bootstrap.load(conn, batch)


@router.get("/status")
def status(c: Container = Depends(container)):
    with c.engine.begin() as conn:
        return c.bootstrap.status(conn)


@router.post("/dry-run")
def dry_run(body: DryRunRequest, c: Container = Depends(container)):
    with c.engine.connect() as conn:      # read-only; rolled back on exit
        return c.bootstrap.dry_run(conn, body)
