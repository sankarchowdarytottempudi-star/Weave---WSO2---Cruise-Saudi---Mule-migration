#!/bin/bash
# Reset the interim gir-test data.  --demo   remove only the DEMO-* seed guests (and their decisions/cases)
#                                    --all    remove EVERYTHING (guests, identities, decisions, cases, batches)
#                                    --seed   (re)load the DEMO-* seed set afterwards
set -euo pipefail
export KUBECONFIG=/root/.kube/config
cd "$(dirname "$0")/../.."
psql() { kubectl -n gir-test exec -i gir-pg-0 -- psql -U postgres -d gir -v ON_ERROR_STOP=1 -qtA; }
for a in "$@"; do case "$a" in
  --all) echo "TRUNCATE gir.review_decision, gir.review_candidate, gir.review_case_projection, gir.identity_decision,
               gir.processing_request, gir.identifier_statistics, gir.guest_match_index, gir.identity_projection,
               gir.bootstrap_batch CASCADE;" | psql; echo "all data removed";;
  --demo) psql <<'SQL'
BEGIN;
DELETE FROM gir.review_decision WHERE case_id IN (SELECT case_id FROM gir.review_case_projection WHERE crm_guest_record_id LIKE 'DEMO-%');
DELETE FROM gir.review_candidate WHERE case_id IN (SELECT case_id FROM gir.review_case_projection WHERE crm_guest_record_id LIKE 'DEMO-%');
DELETE FROM gir.review_case_projection WHERE crm_guest_record_id LIKE 'DEMO-%';
DELETE FROM gir.identity_decision WHERE crm_guest_record_id LIKE 'DEMO-%';
DELETE FROM gir.processing_request WHERE crm_guest_record_id LIKE 'DEMO-%';
CREATE TEMP TABLE demo_ids AS SELECT DISTINCT identity_id FROM gir.guest_match_index WHERE crm_guest_record_id LIKE 'DEMO-%' AND identity_id IS NOT NULL;
DELETE FROM gir.guest_match_index WHERE crm_guest_record_id LIKE 'DEMO-%';
DELETE FROM gir.identity_projection p USING demo_ids d WHERE p.identity_id = d.identity_id
  AND NOT EXISTS (SELECT 1 FROM gir.guest_match_index g WHERE g.identity_id = p.identity_id);
DELETE FROM gir.bootstrap_batch WHERE batch_id LIKE 'demo-%';
COMMIT;
SQL
    echo "demo data removed";;
  --seed) python3 -I tools/load_baseline.py --ndjson-dir deploy/gir-test/demo --url https://13.140.56.229:30960 \
            --cafile /root/.weave-gir/api-tls.crt --token-file /root/.weave-gir/service-token --prefix "demo-$(date +%s)";;
  *) echo "usage: $0 [--demo|--all] [--seed]"; exit 2;;
esac; done
