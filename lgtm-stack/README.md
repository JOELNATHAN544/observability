# LGTM Stack

Comprehensive observability platform consisting of **L**oki, **G**rafana, **T**empo, and **M**imir.

This stack provides correlated logs, metrics, and traces with long-term object storage retention, fully integrated with NGINX Ingress and Cert-Manager for secure access.

**Official Documentation**: [Grafana Loki](https://grafana.com/docs/loki/latest/) | [Grafana Mimir](https://grafana.com/docs/mimir/latest/) | [Grafana Tempo](https://grafana.com/docs/tempo/latest/) | [Grafana](https://grafana.com/docs/grafana/latest/)  
**GitHub**: [grafana/loki](https://github.com/grafana/loki) | [grafana/mimir](https://github.com/grafana/mimir) | [grafana/tempo](https://github.com/grafana/tempo)

---

## Features

- **Unified Observability**: Seamless correlation between Logs (Loki), Metrics (Mimir), and Traces (Tempo).
- **Scalable Storage**: Cloud-native object storage backend (GCS, S3, Azure Blob) for cost-effective retention.
- **Multi-Cloud Ready**: Deploy on GKE, EKS, AKS, or any Kubernetes cluster.
- **Secure Access**: Automated TLS via cert-manager and NGINX Ingress integration.

---

## Deployment Options

Choose your preferred deployment approach:

| Method | Guide | Description |
|--------|-------|-------------|
| **Terraform CLI** | [Terraform Deployment](../docs/lgtm-stack-terraform-deployment.md) | **Recommended**. Complete Infrastructure-as-Code with remote state management. |
| **GitHub Actions** | [Automated CI/CD](../docs/lgtm-stack-github-actions.md) | Fully automated deployment pipelines triggered by pull requests. |
| **Manual** | [Manual Deployment](../docs/manual-lgtm-deployment.md) | Local development and testing using Docker Compose. |

---

## Components

| Component | Purpose | URL (Default) |
|-----------|---------|---------------|
| **Grafana** | Visualization & Dashboards | `https://grafana.example.com` |
| **Loki** | Log Aggregation | `https://loki.example.com` |
| **Mimir** | Metrics Storage (Prometheus) | `https://mimir.example.com` |
| **Tempo** | Distributed Tracing | `https://tempo.example.com` |
| **Prometheus** | Metrics Collection | `https://prometheus.example.com` |

---

## Multi-Tenancy

In a shared observability platform, different teams need access to their own logs, metrics, and traces — without being able to see each other's data. This stack solves that through a combination of **data isolation at the storage layer** (Loki, Mimir, Tempo), **identity management via Keycloak**, and **access control in Grafana** — all wired together automatically.

The core principle is simple: each team is represented by a Keycloak group. The platform discovers those groups and provisions everything needed for that team — a dedicated Grafana Organization, scoped datasources, and a dashboards folder — without any manual steps.

### How it works

| Layer | Mechanism | Effect |
|---|---|---|
| **Data** | `X-Scope-OrgID` header on every request | Loki, Mimir, and Tempo store data in isolated per-tenant buckets |
| **Identity** | Keycloak groups (`<name>-team`) | Single source of truth for tenant membership |
| **Access** | Grafana Organizations + scoped datasources | Users can only query their own tenant's data |
| **Automation** | `grafana-team-sync` CronJob (every 5 min) | Zero-touch provisioning — adding a Keycloak group is all it takes |

### Adding a new tenant

1. Create a group named `<name>-team` in Keycloak and assign users to it.
2. Within 5 minutes, the sync job provisions the Grafana Organization, datasources (Loki, Mimir, Tempo), dashboard folder, and Loki gateway credentials.
3. Users log in and land directly in their tenant's organization — isolated from all others.

For a deeper look at the architecture and security model, see the [Multi-Tenancy Architecture Guide](../docs/multi-tenancy-architecture.md).

---

## Operations

- [Adopting Existing Stack](../docs/adopting-lgtm-stack.md) - Migrate existing monitoring stacks to Terraform management.
- [Troubleshooting Guide](../docs/troubleshooting-lgtm-stack.md) - Common issues and resolutions.
- [Alloy Configuration](../docs/alloy-config.md) - Configure the OpenTelemetry collector.
- [Testing & Verification](../docs/testing-monitoring-stack-deployment.md) - Validation procedures.

---

## Usage Example

### Accessing Dashboards

1.  **Login**: Navigate to your Grafana URL (e.g., `https://grafana.example.com`).
2.  **Credentials**: Log in with `admin` and the password configured in `terraform.tfvars`.
3.  **Explore**: Go to **Explore** in the sidebar.

### Sample Queries

**Logs (Loki):**
```logql
{namespace="lgtm"} |= "error"
```

**Metrics (Mimir):**
```promql
sum(rate(container_cpu_usage_seconds_total{namespace="lgtm"}[5m])) by (pod)
```

**Traces (Tempo):**
Select "Tempo" datasource and enter a Trace ID to visualize the request path.

---

## Additional Resources

- [Terraform State Management](../docs/terraform-state-management.md)
- [Multi-Tenancy Architecture](../docs/multi-tenancy-architecture.md)
