"""Made-up replies of the Otalio System API for the trial run of person-profile-api.

Every call goes to the one integration-tasks path with an operationName. The label says what
was asked: method, operationName, the other query parameter names, and client_name for POSTs.
Scenarios (state["scenario"]): "" answers 200 with made-up data; "not found" answers 404 with a
body; "no detail" answers 502 with no body; "created" answers 201 (the caller must still get 200).
"""
from urllib.parse import parse_qsl


def reply(backend, method, path, query, headers, body, state):
    q = parse_qsl(query or "", keep_blank_values=True)
    op = next((v for k, v in q if k == "operationName"), "?")
    names = ",".join(k for k, _ in q if k != "operationName")
    h = {k.lower(): v for k, v in (headers or {}).items()}
    tag = f"{method} {op} [{names}]" + (f" client={h.get('client_name', '-')}" if method == "POST" else "")
    sc = state.get("scenario") or ""
    if sc == "not found":
        return 404, {"code": "NOT_FOUND", "message": "stand-in: nothing found"}, None, tag
    if sc == "no detail":
        return 502, None, None, tag
    if sc == "created":
        return 201, {"created": True, "operation": op}, None, tag
    if op in ("getPersonByReservationID", "getReservationByID"):
        ship = next((v for k, v in q if k == "shipId"), "")
        return 200, {"operation": op, "shipId": ship, "data": [{"firstName": "Made", "lastName": "Up"}]}, None, tag
    return 200, {"operation": op, "content": [{"id": 1, "name": "made-up"}], "page": 0}, None, tag
