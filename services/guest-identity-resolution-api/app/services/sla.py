"""Review SLA due times in business days (ASSUMPTION: conflicts 1, four-field 2; KSA week Sun-Thu;
public holidays to be provided by the client)."""
from __future__ import annotations

from datetime import datetime, timedelta

from app.config import Settings

FOUR_FIELD = "FOUR_FIELD_REVIEW"


def sla_days(settings: Settings, kind: str) -> int:
    return settings.sla_four_field_days if kind == FOUR_FIELD else settings.sla_conflict_days


def due_time(settings: Settings, kind: str, start: datetime) -> datetime:
    days, t = sla_days(settings, kind), start
    work = set(settings.work_week) or {0, 1, 2, 3, 4}
    while t.weekday() not in work:          # a case opened on a weekend starts on the next work day
        t = (t + timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
    while days > 0:
        t += timedelta(days=1)
        if t.weekday() in work:
            days -= 1
    return t
