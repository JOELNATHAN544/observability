# =============================================================================
# OUTPUTS
# =============================================================================

output "argocd_url" {
  description = "ArgoCD UI URL"
  value = var.deploy_hub ? (
    var.ui_expose_method == "ingress" ?
    "https://${var.argocd_host}" :
    try("https://${data.external.principal_address[0].result.address}", "Pending LoadBalancer IP allocation")
  ) : null
}

output "principal_address" {
  description = "Principal service address (IP or hostname)"
  value = var.deploy_hub ? (
    try(data.external.principal_address[0].result.address, "Pending")
  ) : var.principal_address
}

output "principal_port" {
  description = "Principal service port"
  value = var.deploy_hub ? (
    try(data.external.principal_address[0].result.port, "443")
  ) : var.principal_port
}

output "deployed_agents" {
  description = "List of deployed agent names"
  value       = var.deploy_spokes ? keys(var.workload_clusters) : []
}

output "agent_namespaces_on_hub" {
  description = "Agent management namespaces created on hub"
  value       = var.deploy_spokes ? keys(var.workload_clusters) : []
}

output "keycloak_client_id" {
  description = "Keycloak OIDC client ID"
  value       = var.enable_keycloak && var.deploy_hub ? keycloak_openid_client.argocd[0].client_id : null
}

output "deployment_mode" {
  description = "Deployment mode used"
  value = var.deploy_hub && !var.deploy_spokes ? "hub-only" : (
    var.deploy_hub && var.deploy_spokes ? "full-deployment" : "spoke-only"
  )
}

output "next_steps_hub_only" {
  description = "Next steps for hub-only deployment"
  value = var.deploy_hub && !var.deploy_spokes ? format(
    "Hub deployed! Principal at %s:%s. To add spokes: set deploy_hub=false, deploy_spokes=true, principal_address=%s, principal_port=%s, then terraform apply",
    try(data.external.principal_address[0].result.address, "pending"),
    try(data.external.principal_address[0].result.port, "443"),
    try(data.external.principal_address[0].result.address, "pending"),
    try(data.external.principal_address[0].result.port, "443")
  ) : null
}

output "next_steps_full_deployment" {
  description = "Next steps for full deployment"
  value = var.deploy_hub && var.deploy_spokes ? format(
    "Full deployment complete! ArgoCD UI: %s. Agents: %s. Add more by updating workload_clusters and running terraform apply",
    var.ui_expose_method == "ingress" ? "https://${var.argocd_host}" : try("https://${data.external.principal_address[0].result.address}", "Pending"),
    join(", ", keys(var.workload_clusters))
  ) : null
}

# =============================================================================
# KEYCLOAK OIDC AUTHENTICATION
# =============================================================================

output "keycloak_setup_summary" {
  description = "Summary of Keycloak OIDC setup"
  value = var.enable_keycloak && var.deploy_hub ? format(
    <<-EOT
Keycloak OIDC Configuration:
  Realm: %s
  URL: %s/realms/%s
  Client ID: %s
  Authentication: %s
  Groups Configured: ArgoCDAdmins (admin), ArgoCDDevelopers (edit), ArgoCDViewers (readonly)
EOT
    ,
    var.keycloak_realm,
    var.keycloak_url,
    var.keycloak_realm,
    var.keycloak_client_id,
    var.keycloak_enable_pkce ? "PKCE (CLI enabled)" : "Client Authentication"
  ) : null
}

# =============================================================================
# APPPROJECT MANAGEMENT
# =============================================================================

output "appproject_setup_summary" {
  description = "Summary of AppProject setup for managed mode"
  value = var.enable_appproject_sync ? format(
    <<-EOT
AppProject Configuration for Managed Mode:
  Default AppProject: Configured
  Source Namespaces: %s
  Destination Servers: %s
  Destination Namespaces: %s
  Auto-Sync: Enabled for connected agents
EOT
    ,
    join(", ", var.appproject_default_source_namespaces),
    var.appproject_default_dest_server,
    join(", ", var.appproject_default_dest_namespaces)
  ) : null
}

# =============================================================================
# RESOURCE PROXY & CREDENTIALS
# =============================================================================

output "resource_proxy_setup_summary" {
  description = "Summary of resource proxy setup and credentials management"
  value = var.deploy_hub ? format(
    <<-EOT
Resource Proxy Configuration:
  Service: argocd-agent-resource-proxy.%s.svc.cluster.local:9090
  Credentials Storage: %s
  Agents Configured: %d
  Credential Retrieval: kubectl get secret argocd-agent-resource-proxy-creds -n %s -o jsonpath='{.data.credentials}' | base64 -d
EOT
    ,
    var.hub_namespace,
    var.enable_resource_proxy_credentials_secret ? "Stored in Kubernetes secret" : "In-memory only",
    length(var.workload_clusters),
    var.hub_namespace
  ) : null
}

# =============================================================================
# VERIFICATION COMMANDS
# =============================================================================

output "verification_commands" {
  description = "Useful commands for verification and troubleshooting"
  value = {
    check_hub_argo_cd    = "kubectl get pods -n ${var.hub_namespace} --context ${var.hub_cluster_context}"
    check_principal      = "kubectl logs -n ${var.hub_namespace} deployment/argocd-agent-principal --context ${var.hub_cluster_context}"
    list_agents          = "${var.argocd_agentctl_path} agent list --principal-context ${var.hub_cluster_context} --principal-namespace ${var.hub_namespace}"
    check_appproject_hub = "kubectl get appproject default -n ${var.hub_namespace} --context ${var.hub_cluster_context} -o yaml"
  }
}

# =============================================================================
# PKI BACKUP INSTRUCTIONS
# =============================================================================

output "pki_backup_instructions" {
  description = "CRITICAL: Instructions to backup PKI CA certificate (cannot be regenerated)"
  value = var.deploy_hub ? trimspace(<<-EOT
╔════════════════════════════════════════════════════════════════════════════╗
║                    ⚠️  CRITICAL: BACKUP PKI CA SECRET                      ║
╚════════════════════════════════════════════════════════════════════════════╝

The PKI CA private key is used to sign all agent certificates. If lost, you will
need to re-deploy the entire infrastructure.

BACKUP COMMAND (Run this NOW):
──────────────────────────────

  kubectl get secret argocd-agent-pki-ca -n ${var.hub_namespace} \
    --context ${var.hub_cluster_context} \
    -o yaml > pki-ca-backup-$(date +%Y%m%d-%H%M%S).yaml

SECURE STORAGE:
───────────────
  1. Encrypt the backup:
     gpg --encrypt --recipient your-email@example.com pki-ca-backup-*.yaml
  
  2. Store in a secure location:
     - S3 bucket with encryption (aws s3 cp --sse AES256)
     - Hardware Security Module (HSM)
     - Password manager enterprise vault
     - Encrypted backup solution
  
  3. DO NOT commit to Git
     - Add pki-ca-backup*.yaml to .gitignore
  
  4. Test restore procedure:
     kubectl apply -f pki-ca-backup-YYYYMMDD-HHMMSS.yaml

ALTERNATIVE - External Secrets Management:
──────────────────────────────────────────
  Consider using external secret management:
  - HashiCorp Vault
  - AWS Secrets Manager
  - Google Secret Manager
  - Azure Key Vault
EOT
  ) : null
}

# =============================================================================
# CLEANUP OPERATIONS
# =============================================================================

output "cleanup_summary" {
  description = "Summary of what will be cleaned up with terraform destroy"
  value       = <<-EOT
Terraform destroy will remove:
  ✓ All Hub cluster resources (ArgoCD, Principal, Keycloak clients)
  ✓ All Spoke cluster resources (ArgoCD Agent, certificates)
  ✓ All PKI certificates and signing keys
  ✓ All Kubernetes secrets and ConfigMaps
  ✓ All networking resources (Ingress, LoadBalancer patches)
  ✓ Resource proxy credentials
  ✓ AppProject configurations
  
To completely cleanup:
  1. terraform destroy
  2. Manual cleanup if needed:
     - kubectl delete pdb -n ${var.hub_namespace} --context ${var.hub_cluster_context} (if HA enabled)
     - kubectl delete namespace ${var.hub_namespace} --context ${var.hub_cluster_context}
     - For each spoke: kubectl delete namespace ${var.spoke_namespace} --context <spoke>
EOT
}
