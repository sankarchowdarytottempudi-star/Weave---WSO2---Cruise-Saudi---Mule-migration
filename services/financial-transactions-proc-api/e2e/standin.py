"""Made-up replies for the trial of financial-transactions-proc-api (process-payment chain).
Delays follow the live per-call times measured in seaware-sys (p50, 24 h): login 0.3 s,
reservationsSearch 1.4 s, reservationLock 1.8 s, transactionCreate 0.7 s, reservationStore 6 s,
logout 0.3 s (live max 32.6 s), Telr status 0.8 s. Scenario "slow logout": logout takes 8 s."""
import time

def _gql(body):
    return (body or {}).get("query", "") if isinstance(body, dict) else ""

def reply(backend, method, path, query, headers, body, state):
    sc = state.get("scenario") or ""
    if backend == "telrSysApi":
        time.sleep(0.8)
        return 200, {"order": {"cartid": "RES12345-1", "ref": "TELR-REF-1", "amount": "100.00", "currency": "SAR", "customer": {"ref": "CUST-1"},
                               "status": {"text": "Paid"}}}, None, "telr status"
    if backend == "seawareSysApi":
        q = _gql(body)
        if "login" in q and "mutation" in q:
            time.sleep(0.3); return 200, {"data": {"login": {"token": "stand-in-token"}}}, None, "login"
        if "logout" in q:
            time.sleep(8.0 if sc == "slow logout" else 0.3); return 200, {"data": {"logout": True}}, None, "logout"
        if "reservationsSearch" in q:
            time.sleep(1.4)
            return 200, {"data": {"reservationsSearch": {"edges": [{"node": {"reservation": {
                "key": "12345", "invoiceTotals": {"invoiceTotal": 100, "grossDue": 100},
                "transactions": [], "paymentSchedule": []}}}]}}}, None, "search"
        if "reservationLock" in q:
            time.sleep(1.8); return 200, {"data": {"reservationLock": {"result": True}}}, None, "lock"
        if "transactionCreate" in q:
            time.sleep(0.7); return 200, {"data": {"transactionCreate": {"result": {"id": "T-1"}}}}, None, "create"
        if "reservationStore" in q:
            time.sleep(6.0)
            return 200, {"data": {"reservationStore": {"result": [{"key": "12345",
                "transactions": [{"externalIdent": "TELR-REF-1"}]}], "errors": []}}}, None, "store"
        return 200, {"data": {}}, None, "other"
    if backend == "hTTPDBSystemAPIConfig":
        return 200, {"status": "ok"}, None, "db"
    return 200, {"status": "sent"}, None, "other " + backend
