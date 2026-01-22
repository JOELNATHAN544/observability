# Bug Investigation - ArgoCD Agent Multi-Cluster Setup

## Bug Summary
1.  **Cleanup Script Failure**: `cleanup.sh` fails because `clean_terraform_artifacts` is not defined.
2.  **Terraform Hang**: `data.external.principal_address` hangs during `terraform apply` (refresh phase) because it loops waiting for a LoadBalancer IP of a service (`argocd-agent-principal`) that was deleted by the cleanup script.
3.  **State Mismatch**: Keycloak resources were deleted outside of Terraform, causing plan conflicts.

## Root Cause Analysis
1.  **Missing Function**: `clean_terraform_artifacts` was called in `cleanup.sh` but its definition was missing from the script.
2.  **Aggressive Looping**: The `external` data source in `main.tf` has a 5-minute retry loop that doesn't check if the service even exists before waiting for its LoadBalancer IP.
3.  **Manual Cleanup vs Terraform State**: Using a bash script to delete resources that Terraform manages leads to state inconsistency.
4.  **Namespace Duplication**: `main.tf` had both `kubernetes_namespace` and `null_resource` creating the same namespaces, causing potential conflicts.
5.  **Context Overlap**: `spoke-1` and `spoke-3` are configured to point to the same cluster, causing "AlreadyExists" errors for shared namespaces like `argocd`.
6.  **Shell Escaping Issues**: `kubectl patch` commands in `appproject.tf` and `keycloak.tf` used double quotes that broke when variables (like JSON strings or multi-line configs) contained double quotes.

## Affected Components
- `argocd-agent/scripts/cleanup.sh`
- `argocd-agent/terraform/main.tf`
- `argocd-agent/terraform/appproject.tf`
- `argocd-agent/terraform/keycloak.tf`

## Proposed Solution
1.  **Update `cleanup.sh`**: Define `clean_terraform_artifacts` to clear state files.
2.  **Refactor `principal_address` data source**: Add a service existence check.
3.  **Consolidate Namespace Resources**: Remove redundant `null_resource.hub_agent_namespace`.
4.  **Improve Shell Robustness**: Switch to single-quoted heredocs and better escaping for `kubectl patch`.
5.  **Add Namespace Resilience**: Use `kubectl apply` with heredocs for namespaces to safely handle existing resources.
