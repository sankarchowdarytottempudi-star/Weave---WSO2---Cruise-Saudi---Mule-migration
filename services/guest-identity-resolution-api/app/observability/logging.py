"""Structured JSON logging with masking (section 10.3 / 18): names, phone, email, DOB and ID
values are never written in clear. Only correlation id, reason codes, rule version, timings and
status are logged."""
from __future__ import annotations

import json
import logging
import re
import sys

SENSITIVE_KEYS = {"firstname", "lastname", "dateofbirth", "dob", "phone", "email", "globalid", "loyaltyid",
                  "first_name", "last_name", "display", "comment", "token", "authorization", "password", "secret"}
_EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
_PHONE = re.compile(r"\+?\d[\d\s().-]{6,}\d")


def mask_text(text: str) -> str:
    return _PHONE.sub("<phone>", _EMAIL.sub("<email>", text))


def mask(obj):
    if isinstance(obj, dict):
        return {k: ("<masked>" if k.replace("_", "").lower() in {s.replace("_", "") for s in SENSITIVE_KEYS} else mask(v))
                for k, v in obj.items()}
    if isinstance(obj, list):
        return [mask(v) for v in obj]
    if isinstance(obj, str):
        return mask_text(obj)
    return obj


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        data = {"level": record.levelname, "logger": record.name, "message": mask_text(record.getMessage())}
        extra = getattr(record, "fields", None)
        if isinstance(extra, dict):
            data.update(mask(extra))
        return json.dumps(data, default=str)


def configure() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(logging.INFO)


def log(logger: logging.Logger, message: str, level: int = logging.INFO, **fields) -> None:
    logger.log(level, message, extra={"fields": fields})
