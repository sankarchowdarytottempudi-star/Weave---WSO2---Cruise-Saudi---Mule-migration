# Notes for whoever finishes this service

Written in the Factory ("Finish this migration"). One section per open item.

## payment-reconciliation-scheduler-flow

- 2026-11-15T12:37:40Z: ${financialTransactions.processPaymentPath} on financialTransactionsHTTPRequestConfig http://financial-transactions-proc-api.wso2.svc:80
${dbSysApi.dbPath} on dBSysAPIHTTPRequestConfig http://db-sys-api.wso2.svc:80
${emailSysApi.sendEmailPath} on emailSysAPIHTTPRequestConfig http://email-sys-api.wso2.svc:80
- 2026-11-15T12:38:44Z: ${financialTransactions.processPaymentPath} on financialTransactionsHTTPRequestConfig - http://financial-transactions-proc-api.wso2.svc:80 

${dbSysApi.dbPath} on dBSysAPIHTTPRequestConfig - http://db-sys-api.wso2.svc:80 

${emailSysApi.sendEmailPath} on emailSysAPIHTTPRequestConfig - http://email-sys-api.wso2.svc:80

## Written by hand on 2026-11-15: the timed job

The old application has no operations. It is one job, `payment-reconciliation-scheduler-flow`,
that the old runtime started every 2 minutes. It is now written in `job.bal` (the run),
`modules/core/reconciliation.bal` (reading rows, the retry decision, request bodies) and
`modules/core/email.bal` (the summary e-mail). The line `// source-entry: payment-reconciliation-scheduler-flow`
in `job.bal` marks it.

What one run does: reads the payment audit rows through the DB System API (one Select with the
old query and its three numbers), and for every row decides from the last payment attempt whether
to call `process-payment` again (no attempt yet, status 500, status 400 with TELR_PENDING or
CUSTOM-ERROR). Rows without orderRef or bookingNumber and rows whose last attempt is final are
skipped. At the end it logs the three counts and, when `[email] enabled = true`, sends the summary e-mail.

The timer is OFF: `[aroya.payment_reconciliation_proc_api.scheduler] enabled = false` in
`deploy/vm/config/payment-reconciliation-proc-api.toml`. The old job is still running; with both
on, payments are reconciled twice. At cutover: stop the old job first, set `enabled = true`,
deploy again, and check that the start line of the pod says `timer="ON, every 2 min"`.
Keep one replica; every copy runs the job by itself. With the timer on, the first run starts
as soon as the pod starts (as before), so set replicas to 0 before a redeploy.

Only one run is active at a time (a tick that arrives during a run is skipped with a WARN line),
and a run that fails is logged and the next tick runs normally.

Not checked against the real systems (the job was only run against local stand-ins, because it
writes and sends e-mail): the shape of the real DB System API answer, the real process-payment,
and whether the old platform's edge lets this server in. Log lines do not carry request or
response bodies. Error names in the log and the e-mail follow the old names by status code.

Addresses: process-payment and the e-mail go to the migrated services inside the cluster, as the
notes above say. The database call does NOT go to the in-cluster db-sys-api yet (this server cannot
reach the database privately); it goes to the old DB System API, with this application's own path,
connection key and session id. When the private database connection exists, change
`dBSysAPIHTTPRequestConfig.url` and `dbSysApi.dbPath` to the in-cluster db-sys-api.
