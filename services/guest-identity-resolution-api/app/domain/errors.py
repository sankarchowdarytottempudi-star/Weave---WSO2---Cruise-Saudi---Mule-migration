"""Stable machine-readable error codes (section 9.8). Messages are safe: no PII, no stack traces."""
from __future__ import annotations


class ApiError(Exception):
    def __init__(self, code: str, status: int, message: str, **details):
        super().__init__(message)
        self.code, self.status, self.message, self.details = code, status, message, details


def idempotency_conflict():
    return ApiError("IDEMPOTENCY_CONFLICT", 409, "The same idempotency key was used with a different payload.")


def stale_event():
    return ApiError("STALE_CRM_EVENT", 409, "The event is older than the indexed CRM Modified Time.",
                    reasonCodes=["STALE_CRM_EVENT_REJECTED"], processingState="REJECTED_STALE")


def not_found(what: str):
    return ApiError("NOT_FOUND", 404, f"{what} was not found.")


def invalid_state(message: str):
    return ApiError("INVALID_STATE", 409, message)


def forbidden(message: str = "The caller is not allowed to perform this operation."):
    return ApiError("FORBIDDEN", 403, message)


def unauthorized():
    return ApiError("UNAUTHORIZED", 401, "Service authentication is required.")


def invalid(message: str):
    return ApiError("INVALID_REQUEST", 422, message)
