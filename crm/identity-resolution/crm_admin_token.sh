#!/bin/bash
# Enter a Zoho CRM admin credential for the identity-resolution configuration (self-client refresh token).
# Values are typed hidden, checked read-only (GET /crm/v6/settings/modules), stored only on this server (0600).
set -u
PROFILE=${1:-uat}
case "$PROFILE" in uat|sandbox) ;; *) echo "Profile must be uat or sandbox."; exit 1;; esac
echo "Zoho CRM admin credential — profile: $PROFILE"
echo "Create a Self Client in the Zoho API console with scopes: ZohoCRM.settings.ALL,ZohoCRM.modules.ALL,ZohoCRM.org.READ,ZohoCRM.users.READ"
read -r -p "Accounts URL (e.g. https://accounts.zoho.sa or https://accounts.zoho.com): " ACC
read -r -p "API domain (e.g. https://www.zohoapis.sa; sandbox: https://sandbox.zohoapis.sa): " API
read -r -p "Client ID: " CID
read -r -s -p "Client secret (hidden): " CSEC; echo
read -r -s -p "Refresh token (hidden): " RTOK; echo
export ACC API CID CSEC RTOK PROFILE
python3 - <<'P' || { echo "Nothing changed."; exit 1; }
import json, os, sys, urllib.parse, urllib.request, urllib.error
c = {k: os.environ[v].strip() for k, v in (("accounts_url", "ACC"), ("api_domain", "API"), ("client_id", "CID"), ("client_secret", "CSEC"), ("refresh_token", "RTOK"))}
try:
    r = json.load(urllib.request.urlopen(urllib.request.Request(c["accounts_url"].rstrip("/") + "/oauth/v2/token",
        data=urllib.parse.urlencode({"refresh_token": c["refresh_token"], "client_id": c["client_id"], "client_secret": c["client_secret"], "grant_type": "refresh_token"}).encode()), timeout=30))
except Exception as e:
    print("Zoho accounts could not be reached:", type(e).__name__); sys.exit(1)
if "access_token" not in r:
    print("Zoho refused the credential:", r.get("error", "unknown")); sys.exit(1)
req = urllib.request.Request(c["api_domain"].rstrip("/") + "/crm/v6/settings/modules", headers={"Authorization": "Zoho-oauthtoken " + r["access_token"]})
try:
    m = json.load(urllib.request.urlopen(req, timeout=30))
except urllib.error.HTTPError as e:
    print("The credential cannot read CRM settings (HTTP %d). Check the scopes." % e.code); sys.exit(1)
os.makedirs("/root/.weave-crm", mode=0o700, exist_ok=True)
p = "/root/.weave-crm/%s.json" % os.environ["PROFILE"]
fd = os.open(p + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f: json.dump(c, f)
os.replace(p + ".tmp", p)
print("Accepted: the credential can read %d CRM modules. Saved for profile %s." % (len(m.get("modules", [])), os.environ["PROFILE"]))
P
unset CSEC RTOK
echo "Next: the configuration is applied by the operator (dry run first)."
