# ArgoCD Deployment

This directory contains infrastructure-as-code and configuration for deploying **ArgoCD** to enable GitOps continuous delivery for the Kubernetes cluster.

ArgoCD provides:
*   **GitOps Workflow**: Declarative application deployment from Git repositories.
*   **Automated Sync**: Continuously monitors and synchronizes desired state with live cluster state.
*   **Multi-Cluster Support**: Manage applications across multiple Kubernetes clusters.
*   **OIDC Integration**: Keycloak-based authentication and RBAC.

## Deployment Options

### 1. Automated Deployment (Terraform)
This method uses the Terraform configuration located in the `terraform/` directory. It is the recommended approach for automation.

For detailed instructions, see the [Terraform deployment guide](terraform/) or the `terraform.tfvars.template`.

### 2. Manual (Helm)
If you prefer to deploy manually using Helm, you can follow the [manual deployment guide](../docs/manual-argocd-deployment.md).

The manual deployment uses the production-ready values file located at [`argocd/manual/argocd-prod-values.yaml`](manual/argocd-prod-values.yaml).

## Adoption & Troubleshooting

### Adopting Existing Installation
If you have an existing ArgoCD installation and want to manage it with Terraform, see the [Adoption Guide](../docs/adopting-argocd.md).

### Troubleshooting
For common issues and their solutions, see the [Troubleshooting Guide](../docs/troubleshooting-argocd.md).
