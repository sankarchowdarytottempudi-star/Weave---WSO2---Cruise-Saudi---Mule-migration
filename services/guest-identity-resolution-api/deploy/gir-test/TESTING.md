# Interim Guest Identity Resolution instance (`gir-test`)

> **Warning: this instance holds REAL guest data (PII).** It exists only until the customer's PostgreSQL
> (Tencent) is available. Then the data is migrated there, and this namespace, its volume, its backups and its keys
> are **destroyed** (see the end of this file). Do not copy data out of it and do not share the key.
> The DEMO-* records described below are fake, and you can remove them at any time.

## Address and authentication
| | |
|---|---|
| API | `https://13.140.56.229:30960` (TLS; self-signed certificate) |
| Interactive docs | `https://13.140.56.229:30960/docs`. The browser asks for a login: any user name, **password = the API key**. Then click *Authorize* and paste the key again. |
| API key | read it yourself on the server: `ssh root@13.140.56.229 'cat /root/accept/gir-test-key.txt'` |
| Header | `Authorization: Bearer <key>` on every call except `/health/*` |
| TLS certificate | `ssh root@13.140.56.229 'cat /root/.weave-gir/api-tls.crt' > gir-test.crt`, then `curl --cacert gir-test.crt …` (or `-k` for a quick test) |
| Rate limit | 600 requests per minute per client per pod; `429` + `Retry-After` beyond that |

Network: only the API port is reachable from outside. The database has no route out of the cluster and no route in, except from the API pods.
The API pods can reach only their database: no CRM, no internet (verified).

```bash
KEY=$(ssh root@13.140.56.229 'cat /root/accept/gir-test-key.txt')
API=https://13.140.56.229:30960
curl -sk $API/health/ready
```

## Feature flags on this instance
Shadow-only is **off**; CERTAIN reuse, four-field review and the shadow score are **on**, so every outcome can be exercised.
Pairs are generated with the ported Mule logic (ULID Global ID, `12`+7 digits+check digit Loyalty ID).
Direct scope = source code ∈ {INT-ASSC, INT-CON, NEWINT-CON, MOBAPP, WHATSAPP, IN HOUSE} **and** agency name ∈ the approved AROYA list. Anything else returns `EXCLUDED_NON_DIRECT`.

## Fake DEMO-* seed (load with `deploy/gir-test/reset.sh --seed`)
| guest | name | DOB | phone | e-mail | existing pair |
|---|---|---|---|---|---|
| DEMO-A1 | Zara Testcase | 1980-01-01 | +1 202 555 0101 | zara.testcase@gir-synthetic.invalid | 01DEMOAAAA… / 1290000015 |
| DEMO-B1 | Omar Fakeperson | 1975-06-15 | +1 202 555 0102 | omar.fake@gir-synthetic.invalid | 01DEMOBBBB… / 1290000024 |
| DEMO-C1 | Lina Sampleton | 1990-03-03 | +1 202 555 0103 | lina.sample@gir-synthetic.invalid | 01DEMOCCCC… / 1290000033 |
| DEMO-D1 | Lina Sampleton | 1990-03-03 | +1 202 555 0104 | lina.other@gir-synthetic.invalid | 01DEMODDDD… / 1290000042 |
| DEMO-E1 | Yusuf Placeholder | 1985-09-09 | +1 202 555 0105 | yusuf.p@gir-synthetic.invalid | Global only (incomplete) |

Phones use the fictional `+1 xxx 555 01xx` range. It is valid in libphonenumber, so it exercises phone evidence; `+999` numbers would be invalid and never count.
E-mails use `@gir-synthetic.invalid`.

## Ready example requests
Every evaluate call needs a new `crmGuestRecordId` (use `DEMO-…` so the reset can find it) and a `crmModifiedTime`.
```bash
j() { if [ -n "$1" ]; then printf '"%s"' "$1"; else printf null; fi; }   # JSON string or null
ev() {  # $1 guest id, $2 first, $3 last, $4 dob, $5 phone, $6 email, $7 modified time, $8 source code
cat <<JSON
{"schemaVersion":"1.0","eventId":"$(uuidgen)","eventType":"GUEST_IDENTITY_EVALUATION_REQUESTED",
 "correlationId":"DEMO-$RANDOM","sourceSystem":"GIR_DEMO","sourceRecordId":"$1","crmGuestRecordId":"$1",
 "crmModifiedTime":"${7:-2026-11-17T10:00:00Z}","firstName":"$2","lastName":"$3","dateOfBirth":"$4",
 "phone":$(j "$5"),"email":$(j "$6"),"sourceCode":"${8:-MOBAPP}","agencyName":"AROYA CRUISES MAIN OFFICE"}
JSON
}
post() { curl -sk -X POST $API/v1/guest-identities/evaluate -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d "$1"; echo; }
```
1. **CERTAIN (phone)**: same name, DOB and phone as DEMO-A1, no e-mail. Expect `REUSE_EXISTING_IDENTITY / CERTAIN_PHONE` with pair 01DEMOAAAA… / 1290000015.
   `post "$(ev DEMO-X1 Zara Testcase 1980-01-01 '+1 202 555 0101' '')"`
2. **Four-field review**: DEMO-B1 with a different DOB. Expect `CREATE_PROVISIONAL_IDENTITY / FOUR_FIELD`, `reviewRequired: true`, a new provisional pair and a `reviewCaseId`.
   `post "$(ev DEMO-X2 Omar Fakeperson 1976-06-15 '+1 202 555 0102' omar.fake@gir-synthetic.invalid)"`
3. **New identity**: nobody similar. Expect `CREATE_NEW_IDENTITY / NEW` with a fresh ULID and Loyalty ID.
   `post "$(ev DEMO-X3 Nadia Brandnew 1992-12-12 '+1 202 555 0109' nadia.new@gir-synthetic.invalid)"`
4. **Multiple identities**: the phone matches DEMO-C1 and the e-mail matches DEMO-D1, which are different identities. Expect `CREATE_PROVISIONAL_IDENTITY / MULTIPLE_IDENTITY`, priority HIGH.
   `post "$(ev DEMO-X4 Lina Sampleton 1990-03-03 '+1 202 555 0103' lina.other@gir-synthetic.invalid)"`
5. **Pair repair**: matches DEMO-E1, whose pair is incomplete. Expect `CREATE_PROVISIONAL_IDENTITY / PAIR_REPAIR` (`MATCHED_IDENTITY_NOT_READY`).
   `post "$(ev DEMO-X5 Yusuf Placeholder 1985-09-09 '+1 202 555 0105' '')"`
6. **Stale event**: resend 1 for the same guest with an older time. Expect `409 STALE_CRM_EVENT`.
   `post "$(ev DEMO-X1 Zara Testcase 1980-01-01 '+1 202 555 0101' '' 2026-11-01T00:00:00Z)"`
7. **Out of scope**: source code INT-AGENT. Expect `EXCLUDED_NON_DIRECT`.
   `post "$(ev DEMO-X7 Zara Testcase 1980-01-01 '+1 202 555 0101' '' 2026-11-17T10:00:00Z INT-AGENT)"`

Follow-ups:
- decision state: `GET /v1/guest-identities/decisions/{decisionId}`;
- confirm a CRM write: `POST …/decisions/{id}/commit {"crmIdentityRecordId":"…"}`;
- review case: `GET /v1/review-cases/{caseId}` with headers `X-Reviewer-Id`, `X-Reviewer-Roles: IDENTITY_REVIEWER`, `X-Correlation-Id`.

## Sending your data in bulk (do not send 500,000 single calls)
`POST /v1/bootstrap/batches` indexes existing CRM Guests (plan §16). Up to **5,000 records per call**; **2,000 is recommended**.
It is idempotent per `batchId` (a resend returns the stored counts; the same id with different content returns 409).
It never allocates new pairs and never touches CRM.
Only complete, conflict-free existing pairs become reusable. Global-only pairs are INCOMPLETE. One Loyalty ID under several Global IDs (or the reverse) makes all of them CONFLICT.

JSON:
```bash
curl -sk -X POST $API/v1/bootstrap/batches -H "Authorization: Bearer $KEY" -H 'Content-Type: application/json' -d '{
 "batchId": "crm-2026-11-17-00001",
 "records": [{"crmGuestRecordId":"5725767000012345678","crmModifiedTime":"2026-11-10T08:00:00Z",
   "firstName":"…","lastName":"…","dateOfBirth":"1985-05-10","phone":"966551234567","alternatePhone":"0551234567",
   "email":"…","countryCode":"SA","sourceCode":"MOBAPP","agencyName":"AROYA CRUISES MAIN OFFICE",
   "currentGlobalId":"…","currentLoyaltyId":"…","active":true}]}'
```
NDJSON (one record per line): `curl … -H 'Content-Type: application/x-ndjson' --data-binary @part-00001.ndjson "$API/v1/bootstrap/batches?batchId=crm-00001"`

Field mapping from Zoho Contacts:
- `phone` = Mobile, `alternatePhone` = Phone (both count);
- `sourceCode` = the reservation's Booking_Channel, `agencyName` = Agency_Name;
- `currentGlobalId` = Global_Guest_ID, `currentLoyaltyId` = Aroya_Loyalty_ID;
- `crmModifiedTime` = Modified_Time.

The response gives counts per outcome: `indexed`, `staleSkipped`, `directScope`, `excludedNonDirect`, `linkedToIdentity`, `pendingIdentity`, `identitiesCreated`, `identitiesMarkedConflict`, `durationMs`.

**Alternative, no upload needed:** the encrypted CRM baseline extract already on the server can be loaded server-side, and nothing leaves the VM:
`python3 -I tools/load_baseline.py --extract /root/gen-work/gir-baseline/extract.enc --key /root/gen-work/gir-baseline/extract.key --url https://13.140.56.229:30960 --cafile /root/.weave-gir/api-tls.crt --token-file /root/.weave-gir/service-token --prefix baseline-<date>`

## Progress and counts
- `GET /v1/bootstrap/status`: guests (total / direct / excluded / linked), identities by pair integrity and lifecycle, batches loaded.
- `POST /v1/bootstrap/dry-run {"limit":2000,"afterGuestId":null}`: runs the Phase 1 rules in dry-run (no writes) and returns outcome counts plus `nextAfterGuestId` for the next page.
- `GET /metrics`: Prometheus counters and histograms.

## Measured capacity and performance (500,000 SYNTHETIC rows, 2026-11-17)
| | |
|---|---|
| bulk load | 500,000 records in 250 batches of 2,000: **18.3 min** (about 455 records/s) through the HTTPS API |
| result | 500,000 indexed: 250,205 in direct scope, 299,876 identities, 200,124 pending identity |
| database size | **737 MB** (guest index 388 MB, identities 206 MB, identifier statistics 135 MB) |
| volume | 20 Gi PVC. Estimated 1.5–2 GB once decisions and audit for 500k guests exist. VM disk 47% used (≥ 15% free kept) |
| evaluate latency, 1 client | 1,000 calls: **p50 92 ms, p95 231 ms, p99 418 ms** (target p95 < 500 ms met) |
| evaluate latency, 4 parallel clients | 1,000 calls: p50 204 ms, **p95 477 ms**, p99 761 ms (API pods capped at 1 CPU each) |
| candidates per evaluation | 0: 50%, 1: 46%, 2: 4%, 3: 0.3% (bounded indexed blocks, no full scans) |
| outcomes in the sample | NEW 500, CERTAIN_PHONE 258, PAIR_REPAIR 192, MULTIPLE_IDENTITY 31, CERTAIN_EMAIL 19 |

The synthetic rows were removed after the measurement (`reset.sh --all`). Only the DEMO-* seed is loaded now.

## Reset
On the server, in `/root/gen-work/gir`:
- `deploy/gir-test/reset.sh --demo`: remove only the DEMO-* fake records, their decisions and their cases;
- `deploy/gir-test/reset.sh --demo --seed`: reload the fake seed;
- `deploy/gir-test/reset.sh --all`: remove **everything**, including your data.

## Security and retention
- Display values (names, DOB, phones, e-mails) and Global/Loyalty IDs are stored **encrypted** (AES-256-GCM). The key is generated on the server in `/root/.weave-gir/` (600) with a root-only copy in `/root/.weave-gir-keybackup/`. Matching uses normalized keys only.
- Logs are masked: no names, phones, e-mails, DOBs or IDs.
- A nightly encrypted `pg_dump` goes to `/root/.weave-gir/backups/` (root-only, 7 days), from `/etc/cron.d/gir-test-backup`.
- Payload bodies are not stored; only their hashes are.
- **Destroy procedure** (once the data has moved to the customer PostgreSQL): `kubectl delete ns gir-test` (this deletes the volume), `rm -rf /root/.weave-gir /root/.weave-gir-keybackup /root/accept/gir-test-key.txt /etc/cron.d/gir-test-backup`, then confirm with `kubectl get pv | grep gir-test` (nothing left).
