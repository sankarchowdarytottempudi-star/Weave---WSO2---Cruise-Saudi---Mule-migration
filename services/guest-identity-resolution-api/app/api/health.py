"""GET /health/live and /health/ready (9.2) and /metrics (20.2). No authentication, no data."""
from __future__ import annotations

from fastapi import APIRouter, Depends, Response
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from sqlalchemy import text

from app.api.deps import Container, container

router = APIRouter(tags=["health"])


@router.get("/health/live")
def live():
    return {"status": "UP"}


@router.get("/health/ready")
def ready(response: Response, c: Container = Depends(container)):
    try:
        with c.engine.connect() as conn:
            conn.execute(text("SELECT 1"))
            version = conn.execute(text("SELECT version_num FROM alembic_version")).scalar()
    except Exception:
        response.status_code = 503
        return {"status": "DOWN", "database": "UNAVAILABLE"}
    if not version:
        response.status_code = 503
        return {"status": "DOWN", "database": "NOT_MIGRATED"}
    return {"status": "UP", "database": "UP", "schema": version}


@router.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
