#!/bin/bash
# Guest Identity Resolution - one-command connectivity smoke test, for the day Kafka and the
# customer PostgreSQL are reachable from this cluster.
#
#   deploy/gir/smoke-tomorrow.sh                         # read-only: Kafka metadata + topics, Postgres
#   deploy/gir/smoke-tomorrow.sh --approved-test-topic T # ALSO writes one message to topic T and reads
#                                                        # it back - ONLY with the owner's approval
#
# What it does (nothing else is started, deployed or changed):
#   1. Kafka: a throw-away pod of the guest-identity-integration image, role = smoke, with the
#      worker's own settings Secret: broker metadata (network + TLS + SASL), the three topics and
#      their partitions. Consumer group <group>-smoke, no offsets committed on the real group.
#   2. PostgreSQL: a throw-away pod of the decision-service image with its own Secrets and labels
#      (so its NetworkPolicy applies): connect, TLS, server version, schema privilege, migration
#      state, and a migration DRY-RUN inside one transaction that is rolled back.
# Output: yes/no and counts only - no address, user, secret or data.
set -euo pipefail

WSO2_NS=${WSO2_NS:-wso2}
GIR_NS=${GIR_NS:-gir}
GII_IMAGE=${GII_IMAGE:-guest-identity-integration:candidate}
GIR_IMAGE=${GIR_IMAGE:-guest-identity-resolution-api:1.0.0}
KAFKA_SECRET=${KAFKA_SECRET:-identity-event-worker-config}
TEST_TOPIC=""
if [ "${1:-}" = "--approved-test-topic" ]; then
  TEST_TOPIC=${2:?topic name required}
  echo "Owner-approved write/read round trip on test topic: enabled"
fi
here=$(cd "$(dirname "$0")" && pwd)
fail=0

echo "== preconditions"
for s in "$WSO2_NS/$KAFKA_SECRET" "$GIR_NS/gir-db-owner" "$GIR_NS/gir-db-app" "$GIR_NS/gir-db-ca"; do
  if kubectl -n "${s%%/*}" get secret "${s#*/}" >/dev/null 2>&1; then echo "secret ${s#*/}: present"; else echo "secret ${s#*/}: MISSING"; fail=1; fi
done
[ $fail -eq 0 ] || { echo "Create the missing Secrets first (deploy/gir/CONNECTIVITY-CHECKLIST.md)."; exit 2; }

echo "== Kafka"
args='["-Crole=smoke"'
[ -n "$TEST_TOPIC" ] && args="$args,\"-CsmokeTestTopic=$TEST_TOPIC\""
args="$args]"
kubectl -n "$WSO2_NS" run gir-smoke-kafka --rm -i --restart=Never --quiet --image="$GII_IMAGE" \
  --labels="integration.aroya/layer=process,app.kubernetes.io/name=identity-event-worker" \
  --overrides="{\"spec\":{\"automountServiceAccountToken\":false,\"containers\":[{\"name\":\"gir-smoke-kafka\",\"image\":\"$GII_IMAGE\",\"args\":$args,\"volumeMounts\":[{\"name\":\"config\",\"mountPath\":\"/config\",\"readOnly\":true}],\"securityContext\":{\"allowPrivilegeEscalation\":false,\"readOnlyRootFilesystem\":true,\"capabilities\":{\"drop\":[\"ALL\"]}}}],\"volumes\":[{\"name\":\"config\",\"secret\":{\"secretName\":\"$KAFKA_SECRET\"}}]}}" \
  > /tmp/gir-smoke-kafka.out 2>&1 || fail=1
grep -E '^SMOKE' /tmp/gir-smoke-kafka.out || { echo "Kafka smoke pod gave no result (image or Secret?)"; fail=1; }
grep -q 'FAILED' /tmp/gir-smoke-kafka.out && fail=1
rm -f /tmp/gir-smoke-kafka.out

echo "== PostgreSQL"
values=$(helm -n "$GIR_NS" get values guest-identity-resolution-api -o json 2>/dev/null || echo '{}')
dbhost=$(echo "$values" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("database",{}).get("host",""))')
dbname=$(echo "$values" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("database",{}).get("name",""))')
[ -n "$dbhost" ] && [ -n "$dbname" ] || { dbhost=${GIR_DB_HOST:?set GIR_DB_HOST}; dbname=${GIR_DB_NAME:?set GIR_DB_NAME}; }
kubectl -n "$GIR_NS" create configmap gir-smoke-pg --from-file=pg_smoke.py="$here/pg_smoke.py" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$GIR_NS" run gir-smoke-pg --rm -i --restart=Never --quiet --image="$GIR_IMAGE" \
  --labels="app.kubernetes.io/name=guest-identity-resolution-api,integration.aroya/layer=process" \
  --overrides="{\"spec\":{\"automountServiceAccountToken\":false,\"containers\":[{\"name\":\"gir-smoke-pg\",\"image\":\"$GIR_IMAGE\",\"command\":[\"python\",\"/smoke/pg_smoke.py\"],\"env\":[{\"name\":\"GIR_DB_HOST\",\"value\":\"$dbhost\"},{\"name\":\"GIR_DB_NAME\",\"value\":\"$dbname\"},{\"name\":\"GIR_DB_PORT\",\"value\":\"${GIR_DB_PORT:-5432}\"},{\"name\":\"GIR_DB_SSLMODE\",\"value\":\"${GIR_DB_SSLMODE:-verify-full}\"},{\"name\":\"GIR_DB_SSLROOTCERT\",\"value\":\"/var/run/secrets/gir/db-ca/ca.crt\"},{\"name\":\"GIR_DB_USER\",\"value\":\"${GIR_OWNER_USER:-gir_owner}\"},{\"name\":\"GIR_DB_PASSWORD_FILE\",\"value\":\"/var/run/secrets/gir/db/password\"},{\"name\":\"GIR_APP_DB_USER\",\"value\":\"${GIR_APP_USER:-gir_app}\"},{\"name\":\"GIR_APP_DB_PASSWORD_FILE\",\"value\":\"/var/run/secrets/gir/db-app/password\"},{\"name\":\"GIR_DATABASE_SCHEMA\",\"value\":\"${GIR_SCHEMA:-gir}\"}],\"volumeMounts\":[{\"name\":\"smoke\",\"mountPath\":\"/smoke\",\"readOnly\":true},{\"name\":\"db\",\"mountPath\":\"/var/run/secrets/gir/db\",\"readOnly\":true},{\"name\":\"db-app\",\"mountPath\":\"/var/run/secrets/gir/db-app\",\"readOnly\":true},{\"name\":\"db-ca\",\"mountPath\":\"/var/run/secrets/gir/db-ca\",\"readOnly\":true},{\"name\":\"tmp\",\"mountPath\":\"/tmp\"}],\"securityContext\":{\"allowPrivilegeEscalation\":false,\"readOnlyRootFilesystem\":true,\"capabilities\":{\"drop\":[\"ALL\"]}}}],\"volumes\":[{\"name\":\"smoke\",\"configMap\":{\"name\":\"gir-smoke-pg\"}},{\"name\":\"db\",\"secret\":{\"secretName\":\"gir-db-owner\",\"defaultMode\":256}},{\"name\":\"db-app\",\"secret\":{\"secretName\":\"gir-db-app\",\"defaultMode\":256}},{\"name\":\"db-ca\",\"secret\":{\"secretName\":\"gir-db-ca\",\"defaultMode\":292}},{\"name\":\"tmp\",\"emptyDir\":{}}]}}" \
  > /tmp/gir-smoke-pg.out 2>&1 || fail=1
grep -E '^SMOKE' /tmp/gir-smoke-pg.out || { echo "Postgres smoke pod gave no result (image or Secret?)"; fail=1; }
grep -q 'FAILED' /tmp/gir-smoke-pg.out && fail=1
rm -f /tmp/gir-smoke-pg.out
kubectl -n "$GIR_NS" delete configmap gir-smoke-pg --ignore-not-found >/dev/null

if [ $fail -eq 0 ]; then echo "== result: all checks passed"; else echo "== result: something FAILED - see the lines above"; fi
exit $fail
