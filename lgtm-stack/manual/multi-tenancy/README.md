# LGTM Multi-Tenancy — Local Docker Compose Demo

A minimal, self-contained demonstration of the multi-tenancy model described
in [`lgtm-stack/README.md`](../../README.md#multi-tenancy) and
[`docs/multi-tenancy-architecture.md`](../../../docs/multi-tenancy-architecture.md),
runnable on a single host with Docker Compose.

The full production flow (Keycloak groups → `grafana-team-sync` CronJob →
Grafana Orgs / Loki gateway `.htpasswd`) requires Kubernetes. This demo
focuses on the *data-plane* primitives that actually enforce isolation:

- **Loki** with `auth_enabled: true` — every request requires the
  `X-Scope-OrgID` header.
- **Grafana Organizations** — the strongest isolation boundary in OSS
  Grafana.
- **Tenant-scoped datasources** — each Org's Loki datasource injects a fixed
  `X-Scope-OrgID` header, so users in that Org can only query their own
  tenant's logs.

## What you get

| Tenant | Grafana Org | Viewer user env var | `X-Scope-OrgID` |
|---|---|---|---|
| `tenant-a` | `Tenant A` | `TENANT_A_USER` / `TENANT_A_PASSWORD` | `tenant-a` |
| `tenant-b` | `Tenant B` | `TENANT_B_USER` / `TENANT_B_PASSWORD` | `tenant-b` |

## Prerequisites

- Docker Engine ≥ 20.10, Docker Compose ≥ 2.0
- `curl`, `bash`, `python3` (used by the setup script)

## Run it

```bash
cd lgtm-stack/manual/multi-tenancy

# 1. Seed demo credentials (edit .env if you like — values are loopback-only)
cp .env.example .env

# 2. Start Loki (with auth_enabled: true) and Grafana
docker compose up -d

# 3. Push a few sample logs for each tenant
./push-test-logs.sh

# 4. Provision two Grafana Orgs + viewers + tenant-scoped datasources
./setup-grafana-orgs.sh
```

## Verify isolation

1. Open http://localhost:3000 and log in as `TENANT_A_USER`. Grafana lands
   in the **Tenant A** Org.
2. Go to **Explore**, pick the `Loki (tenant-a)` datasource, run
   `{job="demo"}`. You only see `tenant-a secret data ...` lines.
3. Log out and log in as `TENANT_B_USER` → **Tenant B** Org, `Loki
   (tenant-b)` datasource. Only `tenant-b secret data ...` lines are
   visible.
4. While logged in as `TENANT_A_USER`, there is no way to reach the `Loki
   (tenant-b)` datasource: it only exists inside Org B, to which the
   `tenant-a` user is not a member.

You can also verify at the data plane directly:

```bash
# tenant-a only — tenant-b logs are invisible even with the admin Loki port
curl -G -H 'X-Scope-OrgID: tenant-a' \
  'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="demo"}'

curl -G -H 'X-Scope-OrgID: tenant-b' \
  'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={job="demo"}'
```

## Clean up

```bash
docker compose down -v
```

## Notes

- This demo uses Loki filesystem storage and the single-binary image; the
  production stack uses the distributed chart with object storage
  (`loki-values.yaml`).
- Mimir, Tempo, Keycloak OIDC login and the `grafana-team-sync` CronJob are
  intentionally omitted — they layer *on top* of the same
  `X-Scope-OrgID` + Grafana Org primitives shown here. See
  [`docs/multi-tenancy-architecture.md`](../../../docs/multi-tenancy-architecture.md).
