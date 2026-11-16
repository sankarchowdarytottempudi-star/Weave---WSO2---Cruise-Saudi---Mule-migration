#!/bin/bash
# Creates root-only secrets for the interim gir-test instance and applies it. Never prints a secret.
set -euo pipefail
umask 077
S=/root/.weave-gir; B=/root/.weave-gir-keybackup; IP="${GIR_PUBLIC_IP:?set GIR_PUBLIC_IP}"
mkdir -p "$S" "$S/backups" "$B" /root/accept; chmod 700 "$S" "$S/backups" "$B"
gen() { [ -s "$S/$1" ] || openssl rand -base64 "$2" | tr -d '\n' > "$S/$1"; chmod 600 "$S/$1"; }
gen data-key 32; gen hmac-key 32; gen pg-superuser 24; gen pg-owner 24; gen pg-app 24; gen backup-pass 32
[ -s "$S/service-token" ] || openssl rand -hex 32 | tr -d '\n' > "$S/service-token"; chmod 600 "$S/service-token"
install -m 600 "$S/service-token" /root/accept/gir-test-key.txt
if [ ! -s "$S/pg-tls.key" ]; then
  openssl req -x509 -newkey rsa:3072 -nodes -days 365 -subj "/CN=gir-pg.gir-test.svc" \
    -addext "subjectAltName=DNS:gir-pg-0.gir-pg.gir-test.svc.cluster.local,DNS:gir-pg.gir-test.svc" \
    -keyout "$S/pg-tls.key" -out "$S/pg-tls.crt" 2>/dev/null
  openssl req -x509 -newkey rsa:3072 -nodes -days 365 -subj "/CN=gir-test" -addext "subjectAltName=IP:$IP" \
    -keyout "$S/api-tls.key" -out "$S/api-tls.crt" 2>/dev/null
fi
chmod 600 "$S"/*.key
cp -p "$S"/data-key "$S"/hmac-key "$S"/backup-pass "$B"/       # root-only key backup (the data is unreadable without it)
kubectl get ns gir-test >/dev/null 2>&1 || kubectl create ns gir-test >/dev/null
k() { kubectl -n gir-test create secret "$@" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; }
k generic gir-keys --from-file=data-key="$S/data-key" --from-file=hmac-key="$S/hmac-key" --from-file=service-token="$S/service-token"
k generic gir-pg-passwords --from-file=superuser-password="$S/pg-superuser" --from-file=owner-password="$S/pg-owner" --from-file=app-password="$S/pg-app"
k tls gir-pg-tls --cert="$S/pg-tls.crt" --key="$S/pg-tls.key"
k tls gir-api-tls --cert="$S/api-tls.crt" --key="$S/api-tls.key"
echo "secrets ready"
