# ArgoCD Agent (Hub-and-Spoke Architecture)

Production-grade multi-cluster GitOps with Argo CD Agent Managed Mode for centralized control plane with distributed spoke clusters.

**Official Documentation**: [argo-cd.readthedocs.io/en/stable/operator-manual/agent](https://argo-cd.readthedocs.io/en/stable/operator-manual/agent/)  
**GitHub Repository**: [argoproj/argo-cd](https://github.com/argoproj/argo-cd)

## Features

- **Hub-and-Spoke Architecture**: Centralized control plane (Hub) managing multiple workload clusters (Spokes)
- **Agent Managed Mode**: Secure communication via gRPC with mTLS authentication
- **Local Repo Servers**: Each spoke runs its own repo server for improved security and performance
- **Automated PKI**: Certificate management fully automated via Terraform
- **Flexible Deployment**: Deploy Hub-only, Spoke-only, or both
- **Pattern 1 Support**: Single namespace per spoke for simplified management
- **Reduced Attack Surface**: Application controller runs only on spoke clusters
- **GitOps Workflow**: Applications defined on Hub, deployed on Spokes

## Architecture Overview

### Hub Cluster (Control Plane)
- `argocd-server` - Web UI and API
- `argocd-agent-principal` - Central agent manager
- `redis` - Shared cache
- `applicationset-controller` - ApplicationSet management
- ❌ NO `argocd-application-controller` (runs on Spoke)

### Spoke Cluster (Workload - Headless)
- `argocd-application-controller` - Application reconciliation
- `argocd-repo-server` - Local repository service
- `redis` - Local cache
- `argocd-agent` - Agent client (gRPC to Hub)

### Data Flow (10 Steps)
1. User creates `Application` on Hub in `spoke-XX-mgmt` namespace
2. Hub Principal watches `spoke-XX-mgmt` namespace
3. Principal detects new Application
4. Agent (on Spoke) polls Principal via gRPC
5. Principal sends Application manifest to Agent
6. Agent creates Application on Spoke cluster
7. Spoke's Application Controller picks up Application
8. Controller calls local Repo Server (localhost:8081)
9. Repo Server renders manifests, returns to Controller
10. Controller deploys resources, reports status back

## Deployment

### Automated (Terraform)
Recommended approach with full automation including PKI management.

See [Terraform deployment guide](../docs/argocd-agent-terraform-deployment.md)

### Manual (Kustomize)
For advanced users requiring customizations beyond Terraform capabilities.

Use the scripts in `scripts/` directory for manual deployment.

## Deployment Modes

This module supports three deployment modes:

| Mode | Use Case | Configuration |
|------|----------|---------------|
| **Full** | Deploy both Hub and Spoke | `deploy_hub=true`, `deploy_spoke=true` |
| **Hub-only** | Setup control plane only | `deploy_hub=true`, `deploy_spoke=false` |
| **Spoke-only** | Add additional spoke to existing Hub | `deploy_hub=false`, `deploy_spoke=true` |

## Quick Start

1. **Install Prerequisites**:
   The `argocd-agentctl` binary is required for PKI operations.
   ```bash
   # Downloads and installs to /usr/local/bin (requires sudo)
   ./scripts/install_agentctl.sh
   # Verify
   argocd-agentctl version
   ```

2. **Copy configuration template**:
   ```bash
   cd terraform
   cp terraform.tfvars.template terraform.tfvars
   ```

2. **Edit terraform.tfvars**:
   ```hcl
   hub_cluster_context = "your-hub-context"
   spoke_cluster_context = "your-spoke-context"
   hub_argocd_url = "https://argocd.example.com"
   hub_principal_host = "agent-principal.example.com"
   spoke_id = "spoke-01"
   ```

3. **Deploy**:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. **Verify** (see outputs for detailed instructions)

## Documentation

- **[Architecture](../docs/argocd-agent-architecture.md)**: Detailed architecture, diagrams, and patterns
- **[Terraform Deployment](../docs/argocd-agent-terraform-deployment.md)**: Step-by-step Terraform guide
- **[PKI Management](../docs/argocd-agent-pki-management.md)**: Certificate lifecycle and rotation
- **[Troubleshooting](../docs/argocd-agent-troubleshooting.md)**: Common issues and solutions
- **[Adopting Existing Installation](../docs/adopting-argocd-agent.md)**: Import existing deployment to Terraform

## Requirements

- Terraform >= 1.0
- Kubernetes clusters (Hub and/or Spoke)
- kubectl configured with cluster contexts
- Helm 3.8+ (automatically used by Terraform)
- argocd-agentctl >= v0.5.3 (use provided script)
- Network connectivity from Spoke to Hub (gRPC port 8443)

## Important Considerations

### Timeout Configuration
The agent architecture requires longer timeout values than standard ArgoCD due to the resource-proxy layer adding latency. **The Terraform module automatically configures these timeouts:**

- **Repository Server Timeout**: 300s (5 min) vs default 60s
- **Reconciliation Timeout**: 600s (10 min) vs default 180s
- **Connection Status Cache**: 1h for reduced API load

These are essential for API discovery through the agent connection. See [deployment guide](../docs/argocd-agent-terraform-deployment.md#important-timeout-configuration) for details.

## Security Considerations

- **mTLS Authentication**: Agent uses client certificates signed by Hub CA
- **PKI Automation**: All certificates managed in Terraform state (encrypt remote state!)
- **Least Privilege RBAC**: Principal and Agent have minimal required permissions
- **NetworkPolicies**: Redis access restricted to authorized pods
- **No Hub-to-Spoke Access**: Hub cannot directly reach Spoke clusters

## Scaling to Multiple Spokes

To add additional spokes to an existing Hub:

1. **Create new terraform directory** for the spoke:
   ```bash
   cp -r terraform spoke-02-terraform
   cd spoke-02-terraform
   ```

2. **Configure for Spoke-only**:
   ```hcl
   deploy_hub = false
   deploy_spoke = true
   spoke_id = "spoke-02"
   ```

3. **Deploy**:
   ```bash
   terraform init
   terraform apply
   ```

Alternatively, use Terraform workspaces or modules to manage multiple spokes.

## Access

After deployment:

- **Hub ArgoCD UI**: Access at configured `hub_argocd_url`
- **Create Applications**: In spoke management namespaces (e.g., `spoke-01-mgmt`)
- **Monitor Spokes**: Via Hub UI (applications, sync status, health)

## Operations

- **Certificate Rotation**: See [PKI Management Guide](../docs/argocd-agent-pki-management.md)
- **Adding Spokes**: See scaling section above
- **Monitoring**: Prometheus metrics exposed on Agent and Principal
- **Troubleshooting**: See [Troubleshooting Guide](../docs/argocd-agent-troubleshooting.md)

## Known Issues

| Issue | Solution |
|-------|----------|
| Redis NetworkPolicy blocks Principal | NetworkPolicy includes `argocd-agent-principal` selector |
| Agent authentication fails | `ARGOCD_AGENT_CREDS=""` enables mTLS mode |
| Applications not syncing | Check Agent logs and RBAC permissions |
| Certificate errors | Verify Hub CA and client cert distribution |

See [Troubleshooting Guide](../docs/argocd-agent-troubleshooting.md) for complete list.

## Contributing

This module follows the project's modular architecture patterns. When making changes:

- Follow existing Terraform formatting (`terraform fmt`)
- Update documentation for any architecture changes
- Test all three deployment modes
- Add new issues to troubleshooting guide

## License

See root project LICENSE file.
