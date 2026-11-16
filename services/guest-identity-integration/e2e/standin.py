"""Made-up replies for the closed-room trial of guest-identity-integration (role review).

python    - the Python Guest Identity Decision API (review-case read, decision preparation,
            freshness-failed, commit, fail)
zohoSysApi - Zoho CRM behind zoho-sys-api: one Guest record G1 and its candidate G2

No real system is reached; every value is invented.
"""

T1 = "2026-11-16T10:00:00+00:00"
T2 = "2026-11-16T09:40:00+00:00"


def reply(backend, method, path, query, headers, body, state):
    sc = state.get("scenario") or ""
    if backend == "python":
        if method == "GET" and "/v1/review-cases/" in path:
            return 200, {"caseId": "RC-1", "caseStatus": "REVIEW_OPEN", "kind": "FOUR_FIELD_REVIEW", "priority": "NORMAL",
                         "ruleVersion": "1.0", "reasonCodes": ["FOUR_FIELD_MATCH"], "candidates": []}, None, "review case"
        if path.endswith("/decision-preparations"):
            if sc == "python refuses":
                return 409, {"code": "REVIEW_DATA_CHANGED", "message": "stand-in: changed on screen"}, None, "prepare (refused)"
            return 200, {"reviewDecisionId": "RD-1", "caseId": "RC-1", "state": "REVIEW_DECISION_PREPARED",
                         "action": (body or {}).get("action"),
                         "crmRecordsToCheck": [{"crmGuestRecordId": "G1", "expectedModifiedTime": T1},
                                               {"crmGuestRecordId": "G2", "expectedModifiedTime": T2}],
                         "compareFields": ["firstName", "lastName", "dateOfBirth", "phone", "email", "guestIdentityId"],
                         "crmPatch": {"identityStatus": "CONFIRMED_SAME_PERSON", "reviewCaseId": "RC-1",
                                      "reviewAction": "CONFIRM_SAME_PERSON", "guestIdentityId": "I200",
                                      "aliasIdentityId": "I100"}}, None, "prepare"
        if path.endswith("/freshness-failed"):
            return 200, {"reviewDecisionId": "RD-1", "state": "REVIEW_DATA_CHANGED"}, None, "freshness failed"
        if path.startswith("/py") or True:
            if path.endswith("/commit"):
                return 200, {"reviewDecisionId": "RD-1", "state": "REVIEW_COMMITTED"}, None, "review commit"
            if path.endswith("/fail"):
                return 200, {"reviewDecisionId": "RD-1", "state": "REVIEW_CRM_UPDATE_PENDING"}, None, "review fail"
        return 404, {"code": "NOT_FOUND"}, None, "python other"
    if backend == "zohoSysApi":
        zp = {k.lower(): v for k, v in headers.items()}.get("zohopath", "")
        module = zp.split("/")[3] if zp.count("/") >= 3 else ""
        if method == "GET":
            g2 = "2026-11-16T11:00:00+00:00" if sc == "crm changed" else "2026-11-16T12:40:00+03:00"
            return 200, {"data": [{"id": "G1", "First_Name": "TRIAL", "Modified_Time": T1},
                                  {"id": "G2", "First_Name": "TRIAL", "Modified_Time": g2}]}, None, "crm read"
        if sc == "crm write fails":
            return 500, {"code": "INTERNAL_ERROR", "message": "stand-in: zoho down"}, None, "crm write (refused)"
        kind = "upsert" if zp.endswith("/upsert") else "update"
        return 200, {"data": [{"code": "SUCCESS", "status": "success",
                               "details": {"id": "Z1", "Modified_Time": "2026-11-16T12:00:00+00:00"}}]}, None, f"crm {kind} {module}"
    return 200, {}, None, backend
