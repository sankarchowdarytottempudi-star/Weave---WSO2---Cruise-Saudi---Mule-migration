# Guest Identity Resolution - connectivity checklist (Kafka + PostgreSQL)

Everything else is built and tested. Nothing that needs Kafka or the customer PostgreSQL is
deployed, and `identityResolution.enabled` stays **false** in guest-identity-proc-api. Fill in the
values below, create the Secrets, open the network paths, then run `deploy/gir/smoke-tomorrow.sh`.

## 1. Kafka (customer's existing cluster)

| Value | Where it goes | Notes |
|---|---|---|
| Bootstrap brokers `host:port` (all, private addresses) | `kafkaConfig.bootstrapServers` | the TLS/SASL listener port |
| Security protocol | `kafkaConfig.securityProtocol` | `SASL_SSL` (expected), `SSL` (mTLS not used), `SASL_PLAINTEXT`, `PLAINTEXT` |
| SASL mechanism | `kafkaConfig.saslMechanism` | `SCRAM-SHA-512` (default), `SCRAM-SHA-256` or `PLAIN` |
| SASL user + password (one principal for the integration) | `kafkaConfig.username` / `password` | Secret only |
| Broker CA certificate (PEM) | key `kafka-ca.pem` in the same Secret; `kafkaConfig.caCertPath = "/config/kafka-ca.pem"` | `""` if the brokers use a public CA |
| Topics (create, or confirm they exist) | `evaluationTopic`, `reevaluationTopic`, `dlqTopic` | `guest.identity.evaluation.requested.v1`, `guest.identity.reevaluation.requested.v1`, `guest.identity.processing.dlq.v1`; partitions: 6 suggested (>= worker replicas); retention >= 7 days; DLQ 30 days |
| Consumer group | `kafkaConfig.consumerGroup` | `guest-identity-worker` (+ `guest-identity-worker-smoke` for the smoke test) |
| ACLs for the principal | broker side | WRITE + DESCRIBE on the 3 topics; READ + DESCRIBE on the 2 request topics; READ on groups `guest-identity-worker*`; IdempotentWrite on the cluster (idempotent producer) |
| Optional: an approved test topic | `--approved-test-topic <name>` of the smoke test | only if the owner approves one write/read round trip |

Secrets (namespace `wso2`), each holding `Config.toml` (+ `kafka-ca.pem`):
`identity-event-worker-config` (role worker), `identity-review-api-config` (role review),
`identity-reconciliation-config` (role reconcile). Same Kafka block in all three.

## 2. PostgreSQL (customer's existing instance) - for the Python decision service

| Value | Where it goes | Notes |
|---|---|---|
| Host (private DNS name preferred) + port | Helm `database.host`, `database.port` | `verify-full` needs the name in the certificate |
| Database name | `database.name` | existing database; objects go in schema `gir` |
| Schema owner role + password (DDL, migrations only) | Secret `gir-db-owner` key `password`; `database.migrationUser` | needs CREATE on the database (or a pre-created schema it owns) |
| Runtime role + password (DML only) | Secret `gir-db-app` key `password`; `database.appUser` | granted by the migration |
| sslmode | `database.sslmode` | `verify-full` (default) |
| Server CA certificate | Secret `gir-db-ca` key `ca.crt` | |
| Private CIDR of the database | `database.egressCidr` | for the NetworkPolicy |

## 3. Network rules (cluster -> customer)

- From the k3s node / pod network to every Kafka broker on its SASL_SSL port (bootstrap AND each
  advertised broker address - clients connect to the advertised listeners, not only bootstrap).
- From the k3s node / pod network to PostgreSQL on 5432 (or the given port).
- DNS resolution of the broker and database names from inside the cluster.
- Customer firewall / security groups: allow the cluster's egress address(es).
- Inside the cluster nothing new: worker/review/reconcile pods carry `integration.aroya/layer: process`,
  which the decision service's NetworkPolicy already admits.

## 4. Run the smoke test (read-only)

```
deploy/gir/smoke-tomorrow.sh                          # Kafka metadata + topics; Postgres connect + migration dry-run
deploy/gir/smoke-tomorrow.sh --approved-test-topic T  # adds one message write/read on topic T (owner approval)
```

Prints `SMOKE ... OK/FAILED` lines only (no addresses, users or secrets). Exit 0 = all passed.

## 5. After a green smoke test (owner decisions, in this order)

1. Deploy the decision service (`helm upgrade --install`, migration Job runs) - AV.
2. Deploy `identity-review-api` and `identity-event-worker` (values in `deploy/values/`).
3. Apply the reconciliation CronJob (`suspend: true`), then unsuspend.
4. Enable the CRM workflows (AY), the Workbench (AZ).
5. Last: `sync.identityScopeFields = true` in batch and `identityResolution.enabled = true` in
   guest-identity-proc-api (rollout step 1 keeps Python in shadow mode).
