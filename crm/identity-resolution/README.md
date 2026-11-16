# Zoho CRM configuration — AROYA Direct Guest Identity Resolution (Phase 1, plan v2.1)

What it creates (additive only — nothing existing is renamed, changed or deleted):
- **Contacts (guest module)**: 11 new fields (Guest Identity lookup, Identity Status, Decision Type, Review Case lookup,
  Rule Version, Reason Summary, Processed Time, Source Record ID, Correlation ID, Update Source, Error Code).
  Existing `Global_Guest_ID` and `Aroya_Loyalty_ID` stay as they are and become read-only for users (integration writes them).
- **Guest Identities** (Global ID, Loyalty ID — unique, status, pair integrity, surviving identity, created by, rule version, retired time).
- **Identity Review Cases** (type, status, priority, incoming guest, provisional/selected identity, candidates, reasons, reviewer, SLA, follow-up, Python case id).
- **Identity Decision History** (guest, identity, case, decision id — unique, type, reviewer action, reviewer, rule version, reasons, comment, correlation id, time).
- **Profiles** Identity Reviewer / Identity Supervisor / Identity Audit (cloned from Standard; CRM Administrator = existing Administrator).
- **Webhooks** for re-evaluation and CRM-direct creation, pointing at `IDENTITY_WEBHOOK_URL` (placeholder until the integration is live).
- **Workflows**, created **INACTIVE**: fire only when First Name, Last Name, Date of Birth, Mobile, Phone or Email change
  (identity result fields never trigger them, so no loop), and on CRM-direct guest creation.

## Steps
1. Owner enters the admin credential on the server (hidden prompt, checked read-only, stored 0600):
   `ssh -t root@13.140.56.229 'bash /root/accept/crm_admin_token.sh sandbox'` (if a Zoho sandbox exists) and/or `... uat`
2. Dry run: `python3 crm_config.py plan --profile sandbox` — prints the planned changes, names only.
3. Apply: `python3 crm_config.py apply --profile sandbox`; verify (plan shows nothing left; a test edit of an identity
   result field must not fire the workflow); then the same for `--profile uat`.
4. Rollback: `python3 crm_config.py rollback --profile uat` deactivates the workflows it created; fields/modules are kept.

## Manual steps (no public Zoho API)
- **Web Tab** "Identity Review": Setup → Developer Space → Web Tabs → New; URL = the Workbench page (`WORKBENCH_URL`);
  profiles: Identity Reviewer, Identity Supervisor, Identity Audit, Administrator. Web Tabs need no extra licence.
- **Field permissions**: in each user profile set the fields listed under `readOnlyForUsers` to read-only.
- **Layouts**: the new fields are added to the standard layout by Zoho; arrange them in an "Identity" section.

## Notes
- Requires an edition with custom modules, workflow rules and webhooks (Enterprise or higher); check the org's limits
  for custom modules and fields per module before applying.
- Activation of the workflows happens only when the Integration endpoint is live (iteration 3), by setting
  `IDENTITY_WEBHOOK_URL` on the webhooks and activating the two workflows.
