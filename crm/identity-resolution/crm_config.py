#!/usr/bin/env python3
"""Apply the identity-resolution CRM configuration (spec.json) to a Zoho CRM org.

    python3 crm_config.py plan     [--profile uat|sandbox] [--offline]
    python3 crm_config.py apply    [--profile uat|sandbox]
    python3 crm_config.py rollback [--profile uat|sandbox]

Additive only: modules, fields and picklist values are created when absent; nothing existing is
renamed, changed or deleted. Webhooks are created pointing at the configured URL (placeholder until
the integration is live) and workflows are created INACTIVE. Every created object is recorded in
state/<profile>.json for rollback, which deactivates the workflows it created (fields and modules
with data are never deleted). Credentials come from /root/.weave-crm/<profile>.json, written by
/root/accept/crm_admin_token.sh; no token, secret or record value is ever printed.
"""
import argparse, json, os, sys, time, urllib.error, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = json.load(open(os.path.join(HERE, "spec.json")))
CRED_DIR = "/root/.weave-crm"
TYPE = {"text": "text", "textarea": "textarea", "picklist": "picklist", "lookup": "lookup", "userlookup": "userlookup",
        "datetime": "datetime", "date": "date", "integer": "integer"}


class Zoho:
    def __init__(self, profile):
        c = json.load(open(os.path.join(CRED_DIR, profile + ".json")))
        self.c, self.token, self.exp, self.calls = c, None, 0, 0

    def _tok(self):
        if self.token and time.time() < self.exp - 60:
            return self.token
        data = urllib.parse.urlencode({"refresh_token": self.c["refresh_token"], "client_id": self.c["client_id"],
                                       "client_secret": self.c["client_secret"], "grant_type": "refresh_token"}).encode()
        r = json.load(urllib.request.urlopen(urllib.request.Request(self.c["accounts_url"].rstrip("/") + "/oauth/v2/token", data=data), timeout=30))
        if "access_token" not in r:
            sys.exit("Zoho refused the stored credential (" + str(r.get("error", "unknown")) + "). Run crm_admin_token.sh again.")
        self.token, self.exp = r["access_token"], time.time() + int(r.get("expires_in", 3600))
        return self.token

    def call(self, method, path, body=None):
        self.calls += 1
        time.sleep(0.6)                                     # gentle on the org's API credits
        req = urllib.request.Request(self.c["api_domain"].rstrip("/") + path, method=method,
                                     data=None if body is None else json.dumps(body).encode(),
                                     headers={"Authorization": "Zoho-oauthtoken " + self._tok(), "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                raw = r.read()
                return r.status, (json.loads(raw) if raw else {})
        except urllib.error.HTTPError as e:
            raw = e.read()
            try:
                return e.code, json.loads(raw)
            except ValueError:
                return e.code, {}


def existing(z, offline):
    """Module api names, and per module the field api names + picklist values, read-only."""
    if offline:                                          # names known from the migrated services' code
        guest = set(SPEC["existingGuestFields"].values()) | {"Modified_Time", "Owner"}
        return {"Contacts": {"fields": guest, "picklists": {}}}, {"Standard": "?", "Administrator": "?"}
    st, m = z.call("GET", "/crm/v6/settings/modules")
    if st != 200:
        sys.exit(f"Could not read the modules (HTTP {st}); the credential needs ZohoCRM.settings.ALL.")
    out = {}
    names = [x["api_name"] for x in m.get("modules", [])]
    for api in [SPEC["guestModule"]] + [mod["apiName"] for mod in SPEC["modules"]]:
        if api not in names:
            continue
        st, f = z.call("GET", "/crm/v6/settings/fields?module=" + urllib.parse.quote(api))
        fields = f.get("fields", []) if st == 200 else []
        out[api] = {"fields": {x["api_name"] for x in fields},
                    "picklists": {x["api_name"]: {v.get("actual_value") for v in x.get("pick_list_values") or []}
                                  for x in fields if x.get("data_type") == "picklist"}}
    st, p = z.call("GET", "/crm/v6/settings/profiles")
    profiles = {x["name"]: x["id"] for x in p.get("profiles", [])} if st == 200 else {}
    return out, profiles


def field_body(f):
    b = {"field_label": f["label"], "data_type": TYPE[f["type"]]}
    if f["type"] == "text":
        b["length"] = f.get("length", 255)
    if f["type"] == "textarea":
        b["textarea"] = {"type": "large"}
    if f["type"] == "picklist":
        b["pick_list_values"] = [{"display_value": v, "actual_value": v} for v in SPEC["picklists"][f["values"]]]
    if f["type"] == "lookup":
        b["lookup"] = {"module": {"api_name": f["module"]}}
    if f.get("unique"):
        b["unique"] = {"casesensitive": False}
    return b


def plan(have, profiles):
    steps = []
    for mod in SPEC["modules"]:
        if mod["apiName"] not in have:
            steps.append(("create module", mod["apiName"], mod))
    for mod in [{"apiName": SPEC["guestModule"], "fields": SPEC["guestNewFields"]}] + SPEC["modules"]:
        known = have.get(mod["apiName"], {"fields": set(), "picklists": {}})
        for f in mod["fields"]:
            if f["apiName"] not in known["fields"]:
                steps.append(("create field", mod["apiName"] + "." + f["apiName"], f))
            elif f["type"] == "picklist":
                missing = [v for v in SPEC["picklists"][f["values"]] if v not in known["picklists"].get(f["apiName"], set())]
                if missing:
                    steps.append(("add picklist values", mod["apiName"] + "." + f["apiName"] + " +" + str(len(missing)), (f, missing)))
    for p in SPEC["profiles"]:
        if p["name"] not in profiles:
            steps.append(("clone profile", p["name"] + " from " + p["cloneFrom"], p))
    for w in SPEC["webhooks"]:
        steps.append(("create webhook (if absent)", w["name"], w))
    for w in SPEC["workflows"]:
        steps.append(("create workflow INACTIVE (if absent)", w["name"], w))
    steps.append(("manual", "Web Tab '" + SPEC["webTab"]["name"] + "' (no public API) — see README", None))
    steps.append(("manual", "field-level read-only for: " + ", ".join(SPEC["readOnlyForUsers"]) + " (profile field permissions)", None))
    return steps


def main():
    a = argparse.ArgumentParser()
    a.add_argument("action", choices=["plan", "apply", "rollback"])
    a.add_argument("--profile", default="uat")
    a.add_argument("--offline", action="store_true", help="plan from the code-derived names, no CRM call")
    o = a.parse_args()
    z = None if o.offline else Zoho(o.profile)
    state_path = os.path.join(HERE, "state", o.profile + ".json")
    if o.action == "rollback":
        st = json.load(open(state_path)) if os.path.exists(state_path) else {"workflows": []}
        for wid in st.get("workflows", []):
            code, _ = z.call("PUT", "/crm/v7/settings/automation/workflow_rules/" + wid, {"workflow_rules": [{"id": wid, "status": {"active": False}}]})
            print("deactivate workflow", wid, "->", code)
        print("Fields and modules are kept (they may hold data). Webhooks only fire through the deactivated workflows.")
        return
    have, profiles = existing(z, o.offline)
    steps = plan(have, profiles)
    print(f"{'DRY RUN' if o.action == 'plan' else 'APPLY'} — profile {o.profile}{' (offline)' if o.offline else ''}: {len(steps)} steps")
    for kind, name, _ in steps:
        print(" -", kind + ":", name)
    if o.action == "plan":
        return
    url = os.environ.get("IDENTITY_WEBHOOK_URL", "https://placeholder.invalid/identity-events")
    state = json.load(open(state_path)) if os.path.exists(state_path) else {"modules": [], "fields": [], "profiles": [], "webhooks": [], "workflows": []}
    def names_at(path, key):
        code, r = z.call("GET", path)
        return {x.get("name") for x in (r.get(key) or [])} if code == 200 else set()
    have_hooks = names_at("/crm/v7/settings/automation/webhooks", "webhooks")
    have_flows = names_at("/crm/v7/settings/automation/workflow_rules", "workflow_rules")
    for kind, name, obj in steps:
        if (kind.startswith("create webhook") and name in have_hooks) or (kind.startswith("create workflow") and name in have_flows):
            print(f"   skip {kind}: {name} (already exists)")
            continue
        if kind == "create module":
            ids = [{"id": i} for i in profiles.values() if i != "?"]
            code, r = z.call("POST", "/crm/v6/settings/modules", {"modules": [{"plural_label": obj["plural"], "singular_label": obj["singular"], "profiles": ids}]})
            ok = code in (200, 201); state["modules"] += [name] if ok else []
        elif kind == "create field":
            module, _ = name.split(".", 1)
            code, r = z.call("POST", "/crm/v6/settings/fields?module=" + module, {"fields": [field_body(obj)]})
            ok = code in (200, 201); state["fields"] += [name] if ok else []
        elif kind == "add picklist values":
            f, missing = obj
            module = name.split(".", 1)[0]
            code, r = z.call("GET", "/crm/v6/settings/fields?module=" + module)
            fid = next((x["id"] for x in r.get("fields", []) if x["api_name"] == f["apiName"]), None)
            code, r = z.call("PATCH", f"/crm/v6/settings/fields/{fid}?module={module}", {"fields": [{"id": fid, "pick_list_values": [{"display_value": v, "actual_value": v} for v in missing]}]})
            ok = code in (200, 201)
        elif kind == "clone profile":
            src = profiles.get(obj["cloneFrom"])
            code, r = z.call("POST", f"/crm/v6/settings/profiles/{src}/actions/clone", {"profiles": [{"name": obj["name"], "description": "AROYA identity resolution"}]})
            ok = code in (200, 201); state["profiles"] += [obj["name"]] if ok else []
        elif kind.startswith("create webhook"):
            body = {"webhooks": [{"name": obj["name"], "url": url, "http_method": obj["method"], "module": {"api_name": obj["module"]},
                                  "description": "AROYA identity resolution (inactive until the integration is live)"}]}
            code, r = z.call("POST", "/crm/v7/settings/automation/webhooks", body)
            ok = code in (200, 201)
            if ok:
                state["webhooks"] += [str((r.get("webhooks") or [{}])[0].get("details", {}).get("id", name))]
        elif kind.startswith("create workflow"):
            body = {"workflow_rules": [{"name": obj["name"], "module": {"api_name": obj["module"]}, "status": {"active": False},
                                        "execute_when": {"type": "edit" if obj["trigger"]["on"] == "edit" else "create",
                                                         "details": {"fields": [{"api_name": f} for f in obj["trigger"].get("specificFieldsChanged", [])]}},
                                        "description": "AROYA identity resolution — created inactive"}]}
            code, r = z.call("POST", "/crm/v7/settings/automation/workflow_rules", body)
            ok = code in (200, 201)
            if ok:
                state["workflows"] += [str((r.get("workflow_rules") or [{}])[0].get("details", {}).get("id", name))]
        else:
            code, ok = "-", True
        print(f"   {'ok  ' if ok else 'FAIL'} {kind}: {name} ({code})" + ("" if ok else " — " + str((r or {}).get("code", "")) + " " + str((r or {}).get("message", ""))[:120]))
        os.makedirs(os.path.dirname(state_path), exist_ok=True)
        json.dump(state, open(state_path, "w"), indent=1)
    print("API calls:", z.calls, "| state:", state_path)


if __name__ == "__main__":
    main()
