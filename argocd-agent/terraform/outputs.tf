# =============================================================================
# ARGOCD HUB-AND-SPOKE ARCHITECTURE
# Main orchestration file
# =============================================================================

# =============================================================================
# OUTPUTS
# =============================================================================

output "hub_argocd_url" {
  description = "URL for ArgoCD UI on Hub cluster"
  value       = var.deploy_hub ? var.hub_argocd_url : null
}

output "hub_principal_endpoint" {
  description = "Agent Principal gRPC endpoint"
  value       = var.deploy_hub && var.hub_principal_host != "" ? "${var.hub_principal_host}:8443" : null
}

output "spoke_id" {
  description = "Spoke cluster identifier"
  value       = var.deploy_spoke ? var.spoke_id : null
}

output "spoke_mgmt_namespace" {
  description = "Spoke management namespace on Hub"
  value       = var.deploy_hub && var.deploy_spoke ? local.spoke_mgmt_namespace : null
}

output "ca_certificate_pem" {
  description = "Hub CA certificate in PEM format (managed by argocd-agentctl)"
  value       = null # Managed by argocd-agentctl, retrieve from secret argocd-agent-ca
  sensitive   = true
}

output "spoke_client_cert_pem" {
  description = "Spoke client certificate in PEM format (managed by argocd-agentctl)"
  value       = null # Managed by argocd-agentctl, retrieve from secret argocd-agent-client-tls
  sensitive   = true
}

output "deployment_mode" {
  description = "Current deployment mode"
  value       = var.deploy_hub && var.deploy_spoke ? "full" : (var.deploy_hub ? "hub-only" : (var.deploy_spoke ? "spoke-only" : "none"))
}

output "hub_namespace" {
  description = "ArgoCD namespace on Hub cluster"
  value       = var.deploy_hub ? var.hub_namespace : null
}

output "spoke_namespace" {
  description = "ArgoCD namespace on Spoke cluster"
  value       = var.deploy_spoke ? var.spoke_namespace : null
}

# Instructions for next steps
output "next_steps" {
  description = "Next steps after deployment"
  value       = "Deployment complete! Check outputs for URLs and run: kubectl get pods -n ${var.deploy_hub ? var.hub_namespace : var.spoke_namespace} to verify."
}
