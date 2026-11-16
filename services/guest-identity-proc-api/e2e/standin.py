"""Made-up replies for the trial run of guest-identity-proc-api. Made-up data only.

backend = the settings section of the API that was called. Scenarios (state["scenario"]):
"" registered guest, "not registered", "otp ok", "otp expired", "otp missing", "db down".
"""
import base64
import hashlib
import json
from urllib.parse import parse_qs

OTP_CODE = "246810"
SALT = "trial-salt"
OTP_HASH = base64.b64encode(hashlib.sha256((OTP_CODE + SALT).encode()).digest()).decode()


def _otp_row(expired=False):
    return {"otp_id": "00000000-0000-4000-8000-000000000001", "identifier": "guest@example.invalid", "channel": "email",
            "context": "login", "otp_hash": OTP_HASH, "salt": SALT, "attempts": 0, "max_attempts": 3, "status": "ACTIVE",
            "expires_at": "2001-01-01 00:00:00+00" if expired else "2099-01-01 00:00:00+00",
            "created_at": "2026-01-01 00:00:00+00", "request_id": None, "cs_guest_core_id": "core-1"}


def _reservations():
    guest = {"seqN": 1, "age": 40,
             "client": {"key": 1001, "fullName": "Trial Guest", "firstName": "Trial", "lastName": "Guest",
                        "eMail": "guest@example.invalid", "mobileIntlCode": "900", "mobilePhoneNumber": "5550000"},
             "voyages": [{"pkg": {"key": "PKG1", "name": "Red Sea", "type": {"name": "Cruise", "comments": "4 nights", "key": "C"},
                                  "destinations": [{"name": "Sea", "comments": "Sea"}]},
                          "sail": {"from": {"dateTime": "2099-04-01T16:00:00", "port": {"key": "AAA", "name": "Port A"}},
                                   "to": {"dateTime": "2099-04-05T08:00:00", "port": {"key": "BBB", "name": "Port B"}}},
                          "cabinChain": [{"cabin": {"number": "8012", "category": {"comments": "Suite", "code": "S1"},
                                                    "deck": {"number": 8}}}]}]}
    node = {"key": "R101", "id": "Reservation|R101", "sourceCode": "WEB", "version": 1, "guestCount": 1,
            "initialDate": "2026-01-01T09:00:00", "lastUpdated": "2026-01-03T11:00:00",
            "currency": {"key": "SAR"}, "status": {"name": "Booked", "key": "BK"},
            "invoiceTotals": {"invoiceTotal": 1000, "currentDue": {"amount": 100, "date": "2099-03-01", "type": "D"},
                              "payments": 0, "pendingPayments": 0, "pendingRefunds": 0},
            "contact": {"key": 1001, "fullName": "Trial Guest", "eMail": "guest@example.invalid"},
            "guests": [guest], "language": {"key": "EN"}, "group": None, "agency": None}
    return {"data": {"reservations": {"edges": [{"node": node, "cursor": "c1"}],
                                      "pageInfo": {"hasPreviousPage": False, "hasNextPage": False, "count": 1, "totalCount": 1}}}}


def reply(backend, method, path, query, headers, body, state):
    sc = state.get("scenario") or ""
    q = (body or {}).get("query", "") if isinstance(body, dict) else ""
    if backend == "dbSystemApi":
        if sc == "db down":
            return 503, {"message": "stand-in: guest store down"}, None, "guest store (refused)"
        if "retry_after" in q:
            return 200, [{"retry_after": 0}], None, "lock check"
        if q.startswith("SELECT otp_id, identifier, channel"):
            if sc == "not registered":
                return 200, [], None, "registered check (none)"
            return 200, [{"otp_id": "o-0", "identifier": "guest@example.invalid", "channel": "email", "metadata": {}}], None, "registered check"
        if "count(*) AS cnt" in q:
            return 200, [{"cnt": 0}], None, "rate limit"
        if "FROM cs_guest_mgmt.cs_guest_core WHERE global_guest_id" in q:
            return 200, [{"id": "core-1"}], None, "guest lookup"
        if q.startswith("INSERT INTO cs_guest_mgmt.cs_otp_store"):
            params = (body or {}).get("params") or {}
            ok = bool(params.get("otpHash")) and bool(params.get("salt")) and str(params.get("expiresAt", "")).endswith("+00")
            return 200, {"status": "ok"}, None, "insert otp row" + ("" if ok else " (bad shape)")
        if q.startswith("SELECT * FROM cs_guest_mgmt.cs_otp_store"):
            if sc == "otp missing":
                return 200, [], None, "otp lookup (none)"
            return 200, [_otp_row(expired=(sc == "otp expired"))], None, "otp lookup"
        if "SET status = 'EXPIRED'" in q:
            return 200, {"status": "ok"}, None, "mark expired"
        if "SET status = 'USED'" in q:
            return 200, {"status": "ok"}, None, "mark used"
        if "status = 'verified'" in q:
            return 200, {"status": "ok"}, None, "guest verified"
        if "attempts = attempts + 1" in q:
            return 200, {"status": "ok"}, None, "count wrong code"
        if q.startswith("SELECT attempts, max_attempts"):
            return 200, [{"attempts": 1, "max_attempts": 3, "status": "ACTIVE"}], None, "attempts"
        return 200, {"status": "ok"}, None, "other statement"
    if backend == "zohoSysApi":
        zp = {k.lower(): v for k, v in headers.items()}.get("zohopath", "")
        if zp.endswith("/photo"):
            return 204, None, None, "photo"
        if method == "GET":
            if sc == "not registered":
                return 204, None, None, "crm search (none)"
            return 200, {"data": [{"id": "Z1", "Email": "guest@example.invalid", "Client_ID": "1001", "First_Name": "Trial",
                                   "Last_Name": "Guest"}], "info": {"more_records": False}}, None, "crm search"
        return 200, {"data": [{"code": "SUCCESS", "status": "success", "details": {"id": "Z1"}}]}, None, "crm write"
    if backend == "reservationProcApi":
        if "mutation Login" in q:
            return 200, {"data": {"login": {"token": "stand-in-token"}}}, None, "seaware sign-in"
        if "mutation Logout" in q:
            return 200, {"data": {"logout": True}}, None, "seaware sign-out"
        return 200, _reservations(), None, "seaware reservations"
    if backend == "emailSysApi":
        return 200, {"status": "sent"}, None, "e-mail"
    if backend == "errorMail":
        return 200, {"status": "sent"}, None, "error e-mail"
    if backend == "cmsContentApi":
        return 200, {"data": {"title": "Welcome aboard", "body": "Hello"}}, None, "cms"
    if backend == "identitySupportExpApi":
        return 200, {"guestId": "G-1", "loyaltyId": "L-1"}, None, "id generation"
    return 200, {}, None, backend
