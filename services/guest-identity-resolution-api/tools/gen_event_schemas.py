"""Generates contracts/events/*.schema.json (Kafka event contracts, schemaVersion 1.0).
Run: python tools/gen_event_schemas.py  (the contract test checks the files are up to date)."""
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "contracts" / "events"
BASE = "https://aroya.example/schemas/guest-identity/"


def s(t, **kw):
    return {"type": t, **kw}


def opt(t, **kw):
    return {"type": [t, "null"], **kw}


SNAPSHOT = {
    "schemaVersion": s("string", const="1.0", description="Mandatory; other versions are rejected (11.4)."),
    "eventId": s("string", minLength=1, maxLength=100),
    "idempotencyKey": opt("string", maxLength=300,
                          description="sourceSystem:sourceRecordId:crmModifiedTime; recomputed by Python."),
    "correlationId": s("string", minLength=1, maxLength=100),
    "sourceSystem": s("string", minLength=1, maxLength=50, examples=["SEAWARE", "CRM_DIRECT", "MOBILE"]),
    "sourceRecordId": s("string", minLength=1, maxLength=100),
    "crmGuestRecordId": s("string", minLength=1, maxLength=100),
    "crmModifiedTime": s("string", format="date-time", description="UTC with offset; stale events are rejected."),
    "firstName": opt("string", maxLength=200),
    "lastName": opt("string", maxLength=200),
    "dateOfBirth": opt("string", maxLength=40, description="Original value; normalized only inside Python."),
    "phone": opt("string", maxLength=60, description="Primary personal phone (CRM Mobile)."),
    "alternatePhone": opt("string", maxLength=60, description="Second phone (CRM Phone); also phone evidence."),
    "email": opt("string", maxLength=320),
    "countryCode": opt("string", maxLength=2, description="ISO 3166-1 alpha-2; phone context #2."),
    "citizenshipCode": opt("string", maxLength=2, description="ISO 3166-1 alpha-2; phone context #3."),
    "sourceCode": opt("string", maxLength=50, description="Direct-scope condition 1 (exact after trim+casefold)."),
    "agencyCode": opt("string", maxLength=50, description="Carried for audit; scope fallback only."),
    "agencyName": opt("string", maxLength=200, description="Direct-scope condition 2 (exact after trim+casefold)."),
    "active": s("boolean", default=True),
    "currentGlobalId": opt("string", maxLength=50),
    "currentLoyaltyId": opt("string", maxLength=50),
    "currentIdentityId": opt("string", maxLength=100, description="CRM Guest Identity record ID if already linked."),
}
REQUIRED = ["schemaVersion", "eventId", "eventType", "correlationId", "sourceSystem", "sourceRecordId",
            "crmGuestRecordId", "crmModifiedTime"]
ANY_IDENTITY = {"anyOf": [{"required": [f], "properties": {f: {"type": "string", "minLength": 1}}}
                          for f in ("firstName", "lastName", "dateOfBirth", "phone", "alternatePhone", "email")]}


def snapshot_schema(name, event_type, title, topic):
    props = dict(SNAPSHOT)
    props["eventType"] = s("string", const=event_type)
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": BASE + name, "title": title,
            "description": f"Kafka topic {topic}. Full identity snapshot (D14).", "x-topic": topic,
            "type": "object", "additionalProperties": False, "required": REQUIRED, "properties": props,
            **ANY_IDENTITY}


def dlq_schema():
    return {"$schema": "https://json-schema.org/draft/2020-12/schema", "$id": BASE + "guest-identity-processing-dlq.v1.schema.json",
            "title": "Guest identity processing dead letter", "x-topic": "guest.identity.processing.dlq.v1",
            "description": "Written by the Integration error handler after bounded retries. Carries references and "
                           "a payload HASH only - never the identity values (retention ASSUMPTION, PDPL).",
            "type": "object", "additionalProperties": False,
            "required": ["schemaVersion", "eventId", "correlationId", "originalTopic", "originalEventId",
                         "crmGuestRecordId", "failureStage", "errorCode", "retryable", "attempts", "firstFailureTime",
                         "lastFailureTime", "payloadHash"],
            "properties": {
                "schemaVersion": s("string", const="1.0"),
                "eventId": s("string", minLength=1, maxLength=100),
                "correlationId": s("string", minLength=1, maxLength=100),
                "originalTopic": s("string", enum=["guest.identity.evaluation.requested.v1",
                                                   "guest.identity.reevaluation.requested.v1"]),
                "originalEventId": s("string", maxLength=100),
                "idempotencyKey": opt("string", maxLength=300),
                "crmGuestRecordId": s("string", maxLength=100),
                "decisionId": opt("string", maxLength=40),
                "failureStage": s("string", enum=["VALIDATION", "PYTHON_EVALUATE", "CRM_UPDATE", "PYTHON_COMMIT",
                                                  "PYTHON_FAIL", "UNKNOWN"]),
                "errorCode": s("string", maxLength=100),
                "httpStatus": opt("integer"),
                "retryable": s("boolean"),
                "attempts": s("integer", minimum=1),
                "firstFailureTime": s("string", format="date-time"),
                "lastFailureTime": s("string", format="date-time"),
                "payloadHash": s("string", pattern="^[0-9a-f]{64}$", description="SHA-256 of the original payload."),
                "replayable": s("boolean", default=True),
            }}


FILES = {
    "guest-identity-evaluation-requested.v1.schema.json": snapshot_schema(
        "guest-identity-evaluation-requested.v1.schema.json", "GUEST_IDENTITY_EVALUATION_REQUESTED",
        "Guest identity evaluation requested", "guest.identity.evaluation.requested.v1"),
    "guest-identity-reevaluation-requested.v1.schema.json": snapshot_schema(
        "guest-identity-reevaluation-requested.v1.schema.json", "GUEST_IDENTITY_REEVALUATION_REQUESTED",
        "Guest identity re-evaluation requested", "guest.identity.reevaluation.requested.v1"),
    "guest-identity-processing-dlq.v1.schema.json": dlq_schema(),
}


def render(doc) -> str:
    return json.dumps(doc, indent=2, ensure_ascii=False) + "\n"


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    check = "--check" in sys.argv
    stale = []
    for name, doc in FILES.items():
        path = OUT / name
        if check:
            if not path.exists() or path.read_text() != render(doc):
                stale.append(name)
        else:
            path.write_text(render(doc))
    if stale:
        sys.exit("stale: " + ", ".join(stale))
