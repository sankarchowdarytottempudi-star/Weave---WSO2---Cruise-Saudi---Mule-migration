"""Made-up replies for the trial run of batch (Seaware CRM Data Sync - Incremental).

The trial runner calls reply() for every call the service makes; backend = the settings section
of the API that was called. Made-up data only.
"""
import json, re
from urllib.parse import parse_qs

def guest(key, cabin=True, addons=True):
    g = {"age": 30, "client": {"key": key, "firstName": "First" + key, "lastName": "Last", "gender": "F",
                               "eMail": key.lower() + "@example.test", "title": {"key": "MS"},
                               "citizenship": {"key": "AT", "name": "Atlantis"}, "language": {"key": "EN", "name": "English"},
                               "phones": [{"intlCode": "900", "number": "555" + key[-2:]}],
                               "household": {"key": "H" + key, "addresses": [{"city": "Port City"}]}},
         "voyages": [{"pkg": {"key": "PKG1", "id": "P-1", "sailDays": 4, "type": {"name": "Cruise", "comments": "4 nights"},
                              "destinations": [{"id": "D1", "key": "RS", "name": "Sea", "comments": "Sea"}]},
                      "ship": {"key": "SHIP1"},
                      "sail": {"from": {"dateTime": "2026-04-01T16:00:00", "port": {"id": "1", "key": "AAA", "name": "Port A"}},
                               "to": {"dateTime": "2026-04-05T08:00:00", "port": {"id": "2", "key": "BBB", "name": "Port B"}}},
                      "cabinChain": [{"cabin": {"number": "80" + key[-2:], "category": {"comments": "Suite"}}}] if cabin else [],
                      "promotions": []}]}
    if addons:
        g["shorex"] = [{"price": 75, "name": "Old Town Tour", "code": "SX" + key[-2:], "pkg": {"key": "PKG1", "description": "4 nights"}}]
        g["addons"] = [{"addon": {"key": "SPA", "id": "AD1", "category": {"key": "SPA"}, "type": {"key": "SERVICE"}},
                        "price": 50, "quantity": 1, "isSpecialRequest": False}]
    return g


def edge(key, guests):
    return {"cursor": "c-" + key, "node": {
        "key": key, "id": "Reservation|" + key, "sourceCode": "WEB", "version": 1, "guestCount": len(guests),
        "status": {"name": "Booked"}, "currency": {"key": "SAR"}, "initialDate": "2026-01-01T09:00:00",
        "lastUpdated": "2026-01-03T11:00:00",
        "agency": {"key": "AG1", "isInternal": True, "name": "Agency One", "type": {"key": "TA"}, "phones": [], "addresses": []},
        "commissions": [], "secondaryAgent": None,
        "invoiceTotals": {"invoiceTotal": 1000, "currentDue": {"amount": 100, "date": "2026-03-01T00:00:00"}},
        "group": {"key": "G1", "name": "Group One", "agent": {"key": "GA1", "email": "group@example.test"}},
        "lastInvoice": {"invoiceId": 9000 + int(key[-3:])}, "paymentSchedule": [], "transactions": [], "guests": guests}}


PAGES = [
    {"edges": [edge("R101", [guest("CL11"), guest("CL12", cabin=False, addons=False)]), edge("R102", [guest("CL21")])],
     "pageInfo": {"endCursor": "cursor-page-1", "hasNextPage": True}},
    {"edges": [edge("R103", [guest("CL31")])], "pageInfo": {"endCursor": "cursor-page-2", "hasNextPage": False}},
]


def coql(body):
    return {"data": [], "info": {"more_records": False}}




def _module(zp):
    """The CRM module a call works on, from the zohoPath header: "/crm/v2/Cabin_Info/upsert" -> "Cabin_Info"."""
    parts = [x for x in re.split(r"[/?]", zp or "") if x and not re.match(r"^(crm|v\d+|upsert|search|coql)$", x)]
    return parts[0] if parts else "?"


def reply(backend, method, path, query, headers, body, state):
    """Scenarios (state["scenario"]): "" normal delta run (two pages), "nothing new", "zoho down",
    "seaware sign-in refused", "guest service down", "links exist", "oss down"."""
    sc = state.get("scenario") or ""
    state.setdefault("queries", 0)
    state.setdefault("ids", 0)

    def new_id(prefix):
        state["ids"] += 1
        return "%s-%d" % (prefix, state["ids"])

    if backend == "reservationProc":
        q = (body or {}).get("query", "") if isinstance(body, dict) else ""
        if "mutation Login" in q:
            if sc == "seaware sign-in refused":
                return 401, {"errors": [{"message": "invalid credentials"}]}, None, "Seaware sign-in (refused)"
            return 200, {"data": {"login": {"token": "stand-in-token"}}}, None, "Seaware sign-in"
        i = state["queries"]
        state["queries"] += 1
        empty = {"edges": [], "pageInfo": {"endCursor": None, "hasNextPage": False}}
        page = empty if sc == "nothing new" else (PAGES[i] if i < len(PAGES) else empty)
        return 200, {"data": {"reservations": page}}, None, "Seaware reservations page (%d found)" % len(page["edges"])
    if backend == "zohoSys":
        zp = {k.lower(): v for k, v in headers.items()}.get("zohopath", "")
        mod = _module(zp)
        if method == "GET":
            crit = parse_qs(query).get("criteria", [""])[0]
            if sc == "links exist" and "Reservation_Names" in zp:
                ids = re.findall(r"Reservation_Names:equals:([^)]+)\)", crit)
                if ids:
                    return 200, {"data": [{"id": "L-" + i, "Reservation_Names": {"id": i}, "Guest_Names": {"id": "G-GONE"},
                                           "Modified_By_System": "Seaware"} for i in ids]}, None, "search " + mod
            m = re.search(r"\(Name:in:([^)]+)\)", crit)
            if "Cabin_Info" in zp and m:
                return 200, {"data": [{"id": "Z-old-cabin", "Name": m.group(1) + "|OLD|7000", "Modified_By_System": "Seaware"}]}, None, "search " + mod
            return 204, None, None, "search " + mod
        if zp.endswith("/coql"):
            return 200, coql(body), None, "query " + mod
        if sc == "zoho down":
            return 500, {"code": "INTERNAL_ERROR", "message": "stand-in: CRM is down"}, None, "write " + mod + " (refused)"
        data = body.get("data") if isinstance(body, dict) else None
        records = data if isinstance(data, list) else ([data] if data is not None else [])
        return 200, {"data": [{"code": "SUCCESS", "status": "success", "message": "ok",
                               "details": {"id": new_id("Z")}} for _ in records]}, None, ("update " if method == "PUT" else "write ") + mod
    if backend == "guestIdentityProc":
        if sc == "guest service down":
            return 503, {"message": "stand-in: guest service down"}, None, "guests (refused)"
        guests = body if isinstance(body, list) else [body]
        return 200, [{"zohoId": "G-" + str((g or {}).get("clientId") or (g or {}).get("guestId") or new_id("g")),
                      "status": "success"} for g in guests], None, "guests"
    if backend == "dbSys":
        return 200, {"status": "ok"}, None, "error rows"
    if backend == "mail":
        return 200, {"status": "sent"}, None, "error e-mail"
    if backend == "oss":
        if sc == "oss down":
            return 403, "<Error><Code>AccessDenied</Code></Error>", {"Content-Type": "application/xml"}, "OSS page copy (refused)"
        return 200, "", None, "OSS page copy"
    return 200, {"status": "sent"}, None, "call (" + backend + ")"
