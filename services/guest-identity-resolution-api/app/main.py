"""ASGI entry point: AROYA Direct Guest Identity Resolution API (Phase 1).

Python never calls CRM; the Integration Service (WSO2) owns all CRM reads and writes."""
from __future__ import annotations

from typing import Optional

from fastapi import FastAPI
from sqlalchemy.engine import Engine

from app.api import bootstrap, decisions, errors, evaluation, health, ratelimit, review_cases
from app.api.deps import Container
from app.config import Settings, get_settings
from app.observability.logging import configure
from app.services.pair_allocator import PairAllocator


def create_app(settings: Optional[Settings] = None, engine: Optional[Engine] = None,
               allocator: Optional[PairAllocator] = None) -> FastAPI:
    settings = settings or get_settings()
    if engine is None:
        from app.db.session import get_engine
        engine = get_engine()
    configure()
    app = FastAPI(title="Guest Identity Resolution API", version="1.0.0",
                  docs_url=None, redoc_url=None, openapi_url=None)
    app.state.container = Container.build(settings, engine, allocator)
    errors.install(app)
    ratelimit.install(app, settings.rate_limit_per_minute)
    if settings.docs_enabled:
        _mount_docs(app)
    for r in (evaluation.router, decisions.router, review_cases.router, bootstrap.router, health.router):
        app.include_router(r)
    return app


def _mount_docs(app: FastAPI) -> None:
    from fastapi import Depends
    from fastapi.openapi.docs import get_swagger_ui_html
    from fastapi.responses import JSONResponse

    from app.api.deps import require_docs

    @app.get("/openapi.json", include_in_schema=False, dependencies=[Depends(require_docs)])
    def openapi_json():
        spec = app.openapi()
        spec.setdefault("components", {})["securitySchemes"] = {"serviceToken": {"type": "http", "scheme": "bearer"}}
        spec["security"] = [{"serviceToken": []}]
        return JSONResponse(spec)

    @app.get("/docs", include_in_schema=False, dependencies=[Depends(require_docs)])
    def docs():
        return get_swagger_ui_html(openapi_url="/openapi.json", title="Guest Identity Resolution API")


def app_factory() -> FastAPI:  # uvicorn --factory app.main:app_factory
    return create_app()
