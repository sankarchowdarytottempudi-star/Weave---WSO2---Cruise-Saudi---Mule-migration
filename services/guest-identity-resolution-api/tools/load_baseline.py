"""Server-side bootstrap loader (plan 16): reads the ENCRYPTED baseline extract produced on the VM
(AES-256-GCM over gzip JSON {contacts, accounts, links}) and posts it to /v1/bootstrap/batches in
batches. Nothing is written to disk in clear; no value is printed. Runs on the server only.

usage: python -I tools/load_baseline.py --extract /root/gen-work/gir-baseline/extract.enc \
          --key /root/gen-work/gir-baseline/extract.key --url http://127.0.0.1:18090 \
          --token-file /root/.weave-gir/service-token [--batch-size 2000] [--prefix baseline-2026-11-16]
"""
from __future__ import annotations

import argparse
import gzip
import json
import sys
import time
import urllib.request

DIRECT_DEFAULT = ("INT-ASSC", "INT-CON", "NEWINT-CON", "MOBAPP", "WHATSAPP", "IN HOUSE")


def _id(v):
    return v.get("id") if isinstance(v, dict) else v


def _name(v):
    return v.get("name") if isinstance(v, dict) else v


def decrypt(extract_path: str, key_path: str) -> dict:
    from cryptography.hazmat.primitives.ciphers.aead import AESGCM
    raw = open(extract_path, "rb").read()
    key = open(key_path, "rb").read()
    return json.loads(gzip.decompress(AESGCM(key).decrypt(raw[:12], raw[12:], b"gir-baseline")))


def records(data: dict, direct_sources=DIRECT_DEFAULT):
    accounts = {a["id"]: a for a in data.get("accounts", [])}
    by_contact: dict = {}
    for link in data.get("links", []):
        if str(link.get("Active_Inactive") or "").strip().lower() == "inactive":
            continue
        acc = accounts.get(_id(link.get("Reservation_Names")))
        if acc:
            by_contact.setdefault(_id(link.get("Guest_Names")), []).append(acc)
    norm = lambda s: " ".join(str(s or "").split()).casefold()
    direct = {norm(s) for s in direct_sources}
    for c in data.get("contacts", []):
        accs = by_contact.get(c["id"], [])
        pick = next((a for a in accs if norm(a.get("Booking_Channel")) in direct), accs[0] if accs else {})
        g, l = c.get("Global_Guest_ID") or None, c.get("Aroya_Loyalty_ID") or None
        yield {"crmGuestRecordId": str(c["id"]), "sourceSystem": "CRM_BASELINE", "sourceRecordId": str(c["id"]),
               "crmModifiedTime": c.get("Modified_Time") or "2000-01-01T00:00:00+00:00",
               "firstName": c.get("First_Name"), "lastName": c.get("Last_Name"), "dateOfBirth": c.get("Date_of_Birth"),
               "phone": c.get("Mobile"), "alternatePhone": c.get("Phone"), "email": c.get("Email"),
               "sourceCode": _name(pick.get("Booking_Channel")), "agencyName": _name(pick.get("Agency_Name")),
               "active": True, "currentGlobalId": str(g) if g else None, "currentLoyaltyId": str(l) if l else None}


def post(url: str, token: str, batch_id: str, recs: list) -> dict:
    body = json.dumps({"batchId": batch_id, "records": recs}).encode()
    req = urllib.request.Request(url + "/v1/bootstrap/batches", data=body, method="POST",
                                 headers={"Content-Type": "application/json", "Authorization": "Bearer " + token})
    for attempt in range(5):
        try:
            with urllib.request.urlopen(req, timeout=600) as r:
                return json.loads(r.read())
        except Exception as exc:          # transient: retry the same batch id (idempotent)
            if attempt == 4:
                raise SystemExit(f"batch {batch_id} failed: {type(exc).__name__}")
            time.sleep(2 ** attempt)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--extract", required=True)
    ap.add_argument("--key", required=True)
    ap.add_argument("--url", required=True)
    ap.add_argument("--token-file", required=True)
    ap.add_argument("--batch-size", type=int, default=2000)
    ap.add_argument("--prefix", default="baseline")
    a = ap.parse_args()
    token = open(a.token_file).read().strip()
    data = decrypt(a.extract, a.key)
    totals: dict = {}
    batch, n, started = [], 0, time.monotonic()
    for rec in records(data):
        batch.append(rec)
        if len(batch) == a.batch_size:
            n += 1
            _add(totals, post(a.url, token, f"{a.prefix}-{n:05d}", batch))
            batch = []
            print(f"batch {n}: {totals.get('received', 0)} records, {int(time.monotonic() - started)}s", file=sys.stderr)
    if batch:
        n += 1
        _add(totals, post(a.url, token, f"{a.prefix}-{n:05d}", batch))
    del data
    print(json.dumps({"batches": n, **totals, "seconds": int(time.monotonic() - started)}))


def _add(totals: dict, result: dict) -> None:
    for k, v in result.items():
        if isinstance(v, int) and not isinstance(v, bool) and k != "durationMs":
            totals[k] = totals.get(k, 0) + v


if __name__ == "__main__":
    main()
