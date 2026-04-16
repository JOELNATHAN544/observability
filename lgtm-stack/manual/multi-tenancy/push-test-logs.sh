#!/usr/bin/env bash
# Push a few sample log lines to Loki for two tenants.
#
# Each request carries an `X-Scope-OrgID` header — the only thing Loki uses to
# decide which tenant the log belongs to. Logs pushed for `tenant-a` are not
# visible when querying as `tenant-b`, and vice versa.
set -euo pipefail

LOKI_URL="${LOKI_URL:-http://localhost:3100}"

push_log() {
  local tenant="$1"
  local message="$2"
  local ts
  ts="$(date +%s)000000000"
  curl -sS -f -o /dev/null \
    -H "Content-Type: application/json" \
    -H "X-Scope-OrgID: ${tenant}" \
    -XPOST "${LOKI_URL}/loki/api/v1/push" \
    --data-raw "{\"streams\":[{\"stream\":{\"job\":\"demo\",\"tenant\":\"${tenant}\"},\"values\":[[\"${ts}\",\"${message}\"]]}]}"
  echo "pushed to ${tenant}: ${message}"
}

for i in 1 2 3; do
  push_log "tenant-a" "tenant-a secret data — invoice #${i}"
  push_log "tenant-b" "tenant-b secret data — order #${i}"
  sleep 1
done

echo
echo "Done. Verify per tenant:"
echo "  curl -G -H 'X-Scope-OrgID: tenant-a' '${LOKI_URL}/loki/api/v1/query_range' --data-urlencode 'query={job=\"demo\"}'"
echo "  curl -G -H 'X-Scope-OrgID: tenant-b' '${LOKI_URL}/loki/api/v1/query_range' --data-urlencode 'query={job=\"demo\"}'"
