#!/bin/bash
# Nightly encrypted logical backup of the interim gir-test database. Root-only, 7-day retention.
# Installed as /etc/cron.d/gir-test-backup. Never prints data or keys.
set -euo pipefail
umask 077
export KUBECONFIG=/root/.kube/config
D=/root/.weave-gir/backups; mkdir -p "$D"; chmod 700 "$D"
f="$D/gir-$(date -u +%Y%m%dT%H%M%SZ).dump.enc"
kubectl -n gir-test exec gir-pg-0 -- pg_dump -U postgres -d gir -Fc --no-owner \
  | openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -pass file:/root/.weave-gir/backup-pass -out "$f.part"
mv "$f.part" "$f"
find "$D" -name 'gir-*.dump.enc' -mtime +7 -delete
echo "$(date -u +%FT%TZ) backup ok $(stat -c %s "$f") bytes" >> "$D/backup.log"
# restore: openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass file:/root/.weave-gir/backup-pass -in FILE \
#          | kubectl -n gir-test exec -i gir-pg-0 -- pg_restore -U postgres -d gir --clean --if-exists
