"""Made-up replies for the trial of email-sys: ZeptoMail's HTTPS send API (backend zeptoApi)."""
import time

def reply(backend, method, path, query, headers, body, state):
    if backend == "zeptoApi" and path.endswith("/v1.1/email"):
        time.sleep(0.3)   # a realistic provider answer time
        if state.get("scenario") == "zepto refuses":
            return 422, {"error": {"code": "TM_3201", "details": [{"code": "GE_102"}]}}, None, "zepto refused"
        to = (body or {}).get("to") if isinstance(body, dict) else None
        ok = isinstance(to, list) and to and "htmlbody" in body and "subject" in body and "from" in body
        auth = {k.lower(): v for k, v in headers.items()}.get("authorization", "")
        if not ok or not auth.startswith("Zoho-enczapikey "):
            return 400, {"error": {"code": "STANDIN_BAD_REQUEST"}}, None, "zepto bad request"
        return 201, {"data": [{"code": "EM_104"}], "request_id": "stand-in-1"}, None, "zepto send"
    return 200, {}, None, ""
