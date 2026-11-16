"""Stable machine-readable error responses (9.8): no stack traces, no PII, no input echo."""
from __future__ import annotations

import logging

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.domain.errors import ApiError
from app.observability import metrics
from app.observability.logging import log

logger = logging.getLogger("gir.api")


def install(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api(request: Request, exc: ApiError):
        metrics.ERRORS.labels(exc.code).inc()
        details = dict(exc.details)
        headers = details.pop("_headers", None)
        return JSONResponse(status_code=exc.status, content={"code": exc.code, "message": exc.message, **details},
                            headers=headers)

    @app.exception_handler(RequestValidationError)
    async def _validation(request: Request, exc: RequestValidationError):
        metrics.ERRORS.labels("INVALID_REQUEST").inc()
        fields = [{"field": ".".join(str(p) for p in e.get("loc", ()) if p != "body"), "problem": e.get("type")}
                  for e in exc.errors()]                      # never the submitted value
        return JSONResponse(status_code=422, content={"code": "INVALID_REQUEST",
                                                      "message": "The request is not valid.", "fields": fields})

    @app.exception_handler(Exception)
    async def _unexpected(request: Request, exc: Exception):
        metrics.ERRORS.labels("INTERNAL_ERROR").inc()
        log(logger, "unexpected error", level=logging.ERROR, errorType=type(exc).__name__)
        return JSONResponse(status_code=500, content={"code": "INTERNAL_ERROR",
                                                      "message": "The request could not be processed."})
