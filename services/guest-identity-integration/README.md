# guest-identity-integration

The WSO2/Ballerina Integration Service side of AROYA **Direct Guest Identity Resolution** (plan v2.1).
It owns every CRM read and write and every Kafka message; the Python decision service
(`services/guest-identity-resolution-api`) owns every identity decision. Nothing here matches guests:
Python's decision and `crmPatch` are applied exactly as returned.

One image, three Helm releases chosen by `role`:

| Release | role | What it does |
|---|---|---|
| `identity-event-worker` | `worker` | Consumes `guest.identity.evaluation.requested.v1` and `guest.identity.reevaluation.requested.v1`; calls Python evaluate/re-evaluate; writes the pair, status, reasons and review case to CRM via zoho-sys-api; commits in Python; bounded retries with backoff; DLQ `guest.identity.processing.dlq.v1`. |
| `identity-review-api` | `review` | Review API for the Workbench (`GET /review-cases/{caseId}`, `POST /review-cases/{caseId}/decisions`), the CRM workflow webhook and the ingress endpoint (`POST /crm-events`). |
| `identity-reconciliation` (CronJob) | `reconcile` | Nightly delta reconciliation (plan 17); runs once and exits. |
| (one-off pod) | `smoke` | Kafka connectivity check used by `deploy/gir/smoke-tomorrow.sh`. |

## Flows

**Worker (plan 14.1, 14.5).** Per event: validate → Python evaluate (or re-evaluate) →
- `409 STALE_CRM_EVENT` → done (out-of-order event, nothing applied);
- decision `COMMITTED` / `crmUpdateRequired: false` → done (duplicate event, excluded guest, keep-existing);
- otherwise, in order: upsert `Guest_Identities` by `Global_ID` when Python reserved a new pair →
  update the Contact (`Guest_Identity`, IDs, `Identity_*` fields; `trigger: []` so the identity-field
  webhook never fires on our own write) → upsert `Identity_Review_Cases` by `Case_ID` when a review is
  required → Python commit.
- CRM failure → Python `fail(retryable)` → retry the event: Python returns the **same decision**
  (idempotency key), the same pair is written again. A second pair is never requested.
- Commit failure after CRM success → only the commit is retried; if it still fails the event is
  retried, then dead-lettered (`retryable: true`), and the reconciliation commits it.
- A pair different from the Guest's current Global ID is refused (`ID_CHANGE_REFUSED`): committed
  IDs are never changed here.
- Records are processed one at a time per poll, offsets committed after the batch is finished
  (manual commit). If the DLQ cannot be written the batch is not committed and is read again.
  Partition key = CRM Guest record id, so events of one Guest stay in order.

**Review decision (plan 10.4).** Authenticate → Python `decision-preparations` (Python checks the
versions shown) → **one** batched CRM read of `crmRecordsToCheck` → compare Modified Time / identity
link / presence → on any difference: Python `freshness-failed` with the full latest snapshots, CRM
untouched, `409 REVIEW_DATA_CHANGED` → otherwise apply `crmPatch` in order (alias identity, household
identities, Guest, review case mirror) → Python commit (same review decision id). CRM failure →
Python `fail(retryable)` → `502 REVIEW_CRM_UPDATE_PENDING` (submit again = same decision). Opening a
case makes **zero** CRM calls.

**Webhook / ingress (plan 14.2, 14.3).** `POST /crm-events` with `X-Webhook-Token`:
- CRM workflow: `{"eventType": "created" | "updated", "record": { ...full Contact incl. Modified_Time... }}`
  → `created` → evaluation topic (source system `CRM_DIRECT`), `updated` → re-evaluation topic.
- guest-identity-proc-api: a ready schema-1.0 evaluation event → evaluation topic.
- Kafka not set or down → `503 EVENT_NOT_PUBLISHED`; the Guest stays `PENDING_IDENTITY` and the
  reconciliation republishes it.

**Reconciliation (plan 17).** Redis lock (single run) + `concurrencyPolicy: Forbid`; watermark in Redis.
COQL delta of in-scope Contacts modified after the watermark: decisions CRM already shows but Python
has not committed are committed; Guests with an identity get a re-evaluation snapshot (Python
refreshes keys, rejects stale ones). Guests `PENDING_IDENTITY` for longer than `pendingAfterMinutes`
get their evaluation republished. The watermark advances only when every page and record succeeded.
It never writes an identity to CRM.

## Reviewer authentication (contract with the Review Workbench)

The Workbench backend (not the browser) calls the Review API with two headers:

- `X-Reviewer-Context`: base64url (no padding) of the JSON `{"userId": "<CRM user id>", "roles": ["IDENTITY_REVIEWER" | "IDENTITY_SUPERVISOR" | "IDENTITY_AUDIT", ...], "exp": <unix seconds>}`
- `X-Reviewer-Signature`: lowercase hex HMAC-SHA256 of the exact `X-Reviewer-Context` string with the shared secret `reviewAuth.signingSecret`

`exp` must be in the future and at most `reviewAuth.maxAgeSeconds` (default 300) ahead. Open a case:
any of the three roles. Decide: `IDENTITY_REVIEWER` or `IDENTITY_SUPERVISOR`; `REVERSE_DECISION`:
`IDENTITY_SUPERVISOR` only. The user and roles are forwarded to Python as `X-Reviewer-Id` /
`X-Reviewer-Roles`. Errors: `401 UNAUTHORIZED` (missing, bad signature, expired), `403 FORBIDDEN`,
`503 REVIEW_AUTH_NOT_CONFIGURED` (no secret set).

`POST /review-cases/{caseId}/decisions` body: `{"action", "selectedIdentityId"?, "comment"?,
"versionsShown": [{"crmGuestRecordId", "crmModifiedTime"}], "idempotencyKey", "followUpDate"?}`.
Answers: `200 {reviewDecisionId, caseId, state: REVIEW_COMMITTED}`, `409 REVIEW_DATA_CHANGED`
(`changedRecords`), `502/503 REVIEW_CRM_UPDATE_PENDING` (submit again with the same idempotency key),
`202 REVIEW_CRM_UPDATE_PENDING` (CRM updated, commit pending), or Python's own error passed through.

## Settings

`Config.toml.example` lists every key. Kafka and the CRM are pure configuration; with
`kafkaConfig.bootstrapServers = []` the worker does not start (readiness stays DOWN), publishing
answers 503, and nothing else changes. Field and module API names are configurable
(`crmFields`, `crmModules`) because Zoho confirms new API names on creation.

## Tests

`bal test --code-coverage` (from this folder, inside the workspace): 44 tests, package line
coverage 82.3% (`modules/core` 100%; root module 75.3% - the uncovered part is the Kafka consumer
loop, the Kafka producer and the smoke role, which need a broker). Python, CRM and Kafka are in-memory stand-ins
(`tests/standins.bal`); the HTTP wiring runs against HTTP stand-ins on loopback. Covered plan 21.3
scenarios: source guest end to end, duplicate event, CRM update fails → retry same pair, commit
fails after CRM success, open review = zero CRM calls, unchanged submit = exactly one CRM read,
CRM changed before submit → REVIEW_DATA_CHANGED, out-of-order event; plus Python down → DLQ,
DLQ down → offset not committed, ID change refused, reconciliation watermark/lock/commit.

Closed-room trial: `e2e/trial.json` + `e2e/standin.py` (role review, Kafka not set).
