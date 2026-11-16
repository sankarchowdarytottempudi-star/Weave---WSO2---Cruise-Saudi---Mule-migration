"""Simple per-client sliding-window rate limit (interim/test instances without a gateway).
Health probes are exempt. Production relies on the WSO2 gateway's throttling policies."""
from __future__ import annotations

import threading
import time
from collections import defaultdict, deque

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from app.observability import metrics


def install(app: FastAPI, per_minute: int) -> None:
    if per_minute <= 0:
        return
    hits: dict = defaultdict(deque)
    guard = threading.Lock()

    @app.middleware("http")
    async def _limit(request: Request, call_next):
        if request.url.path.startswith("/health"):
            return await call_next(request)
        client = request.client.host if request.client else "unknown"
        now = time.monotonic()
        with guard:
            q = hits[client]
            while q and now - q[0] > 60:
                q.popleft()
            if len(q) >= per_minute:
                metrics.ERRORS.labels("RATE_LIMITED").inc()
                return JSONResponse(status_code=429, headers={"Retry-After": "60"},
                                    content={"code": "RATE_LIMITED", "message": "Too many requests; retry later."})
            q.append(now)
        return await call_next(request)
