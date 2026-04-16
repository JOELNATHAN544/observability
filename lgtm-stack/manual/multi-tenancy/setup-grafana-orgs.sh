#!/usr/bin/env bash
# Provision two Grafana Organizations, tenant-scoped Loki datasources and a
# viewer user per Org — the same model the production `grafana-team-sync`
# CronJob applies on top of Keycloak groups, done here via the Grafana HTTP
# API for the local demo.
#
# Each Organization gets exactly one Loki datasource that injects
# `X-Scope-OrgID: <tenant>` on every request, so users inside that Org can
# only query their own tenant's data. Because Grafana Organizations are the
# strongest isolation boundary in OSS Grafana, users in Org A cannot see
# Org B's datasources, folders or dashboards at all.
#
# Credentials are loaded from `.env` (see `.env.example`). These are
# demo-only values for the loopback-only Docker Compose stack — NOT real
# secrets.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SCRIPT_DIR}/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${SCRIPT_DIR}/.env"
  set +a
fi

: "${GF_ADMIN_USER:?GF_ADMIN_USER must be set (see .env.example)}"
: "${GF_ADMIN_PASSWORD:?GF_ADMIN_PASSWORD must be set (see .env.example)}"
: "${TENANT_A_USER:?TENANT_A_USER must be set (see .env.example)}"
: "${TENANT_A_PASSWORD:?TENANT_A_PASSWORD must be set (see .env.example)}"
: "${TENANT_B_USER:?TENANT_B_USER must be set (see .env.example)}"
: "${TENANT_B_PASSWORD:?TENANT_B_PASSWORD must be set (see .env.example)}"

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
ADMIN_AUTH="${GF_ADMIN_USER}:${GF_ADMIN_PASSWORD}"

# Loki is reachable from Grafana over the compose network at http://loki:3100.
# Override if you run the script outside the compose network.
LOKI_URL_FROM_GRAFANA="${LOKI_URL_FROM_GRAFANA:-http://loki:3100}"

TENANTS=(
  "tenant-a|Tenant A|${TENANT_A_USER}|${TENANT_A_PASSWORD}"
  "tenant-b|Tenant B|${TENANT_B_USER}|${TENANT_B_PASSWORD}"
)

api() {
  local method="$1" path="$2"
  shift 2
  curl -sS -u "${ADMIN_AUTH}" -H "Content-Type: application/json" \
    -X "${method}" "${GRAFANA_URL}${path}" "$@"
}

api_in_org() {
  local org_id="$1" method="$2" path="$3"
  shift 3
  curl -sS -u "${ADMIN_AUTH}" \
    -H "Content-Type: application/json" \
    -H "X-Grafana-Org-Id: ${org_id}" \
    -X "${method}" "${GRAFANA_URL}${path}" "$@"
}

upsert_org() {
  local name="$1"
  local existing
  existing="$(api GET "/api/orgs/name/$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "${name}")" || true)"
  if echo "${existing}" | grep -q '"id"'; then
    echo "${existing}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])'
    return
  fi
  api POST "/api/orgs" --data "$(printf '{"name":"%s"}' "${name}")" \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["orgId"])'
}

upsert_user() {
  local login="$1" password="$2"
  local existing
  existing="$(api GET "/api/users/lookup?loginOrEmail=${login}" || true)"
  if echo "${existing}" | grep -q '"id"'; then
    echo "${existing}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])'
    return
  fi
  api POST "/api/admin/users" \
    --data "$(printf '{"name":"%s","login":"%s","password":"%s","email":"%s@example.com"}' \
      "${login}" "${login}" "${password}" "${login}")" \
    | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])'
}

add_user_to_org() {
  local org_id="$1" login="$2" role="$3"
  # Grafana returns 409 if the user is already a member — treat that as success.
  local body
  body="$(api POST "/api/orgs/${org_id}/users" \
    --data "$(printf '{"loginOrEmail":"%s","role":"%s"}' "${login}" "${role}")" || true)"
  if echo "${body}" | grep -q "already added"; then
    # Update the role just in case.
    api PATCH "/api/orgs/${org_id}/users/$(api GET "/api/users/lookup?loginOrEmail=${login}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')" \
      --data "$(printf '{"role":"%s"}' "${role}")" >/dev/null || true
  fi
}

remove_user_from_default_org() {
  # Admin user is in Org 1 (Main Org.) and every new user is added there by
  # default. Drop the tenant viewers from Org 1 so they only belong to their
  # tenant's Organization.
  local login="$1"
  local user_id
  user_id="$(api GET "/api/users/lookup?loginOrEmail=${login}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')"
  api DELETE "/api/orgs/1/users/${user_id}" >/dev/null 2>&1 || true
}

upsert_loki_datasource() {
  local org_id="$1" tenant="$2"
  local ds_name="Loki (${tenant})"
  local existing
  existing="$(api_in_org "${org_id}" GET "/api/datasources/name/$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "${ds_name}")" || true)"
  local payload
  payload="$(python3 -c '
import json, sys
name, url, tenant = sys.argv[1:]
print(json.dumps({
    "name": name,
    "type": "loki",
    "access": "proxy",
    "url": url,
    "isDefault": True,
    "jsonData": {
        "httpHeaderName1": "X-Scope-OrgID",
    },
    "secureJsonData": {
        "httpHeaderValue1": tenant,
    },
}))
' "${ds_name}" "${LOKI_URL_FROM_GRAFANA}" "${tenant}")"
  if echo "${existing}" | grep -q '"id"'; then
    local ds_id
    ds_id="$(echo "${existing}" | python3 -c 'import json,sys;print(json.load(sys.stdin)["id"])')"
    api_in_org "${org_id}" PUT "/api/datasources/${ds_id}" --data "${payload}" >/dev/null
  else
    api_in_org "${org_id}" POST "/api/datasources" --data "${payload}" >/dev/null
  fi
}

echo "Waiting for Grafana at ${GRAFANA_URL} ..."
for i in $(seq 1 60); do
  if curl -sS -f -u "${ADMIN_AUTH}" "${GRAFANA_URL}/api/health" >/dev/null; then
    break
  fi
  sleep 2
done

for entry in "${TENANTS[@]}"; do
  IFS="|" read -r tenant org_name user_login user_pw <<<"${entry}"

  echo "==> ${org_name} (${tenant})"
  org_id="$(upsert_org "${org_name}")"
  echo "    org id: ${org_id}"

  upsert_loki_datasource "${org_id}" "${tenant}"
  echo "    datasource 'Loki (${tenant})' provisioned with X-Scope-OrgID=${tenant}"

  user_id="$(upsert_user "${user_login}" "${user_pw}")"
  echo "    user: ${user_login} (id=${user_id})"

  add_user_to_org "${org_id}" "${user_login}" "Viewer"
  remove_user_from_default_org "${user_login}"
done

echo
echo "Setup complete."
echo "  URL:       ${GRAFANA_URL}"
echo "  Tenant A:  ${TENANT_A_USER}  ->  Org 'Tenant A'"
echo "  Tenant B:  ${TENANT_B_USER}  ->  Org 'Tenant B'"
