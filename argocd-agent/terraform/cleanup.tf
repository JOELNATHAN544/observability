# =============================================================================
# CLEANUP & DESTRUCTION RESOURCES
# Ensures complete removal of all created resources
# =============================================================================

# =============================================================================
# SECTION 1: KEYCLOAK CLEANUP
# =============================================================================

# Delete Keycloak clients and realm when destroying
resource "null_resource" "keycloak_cleanup" {
  count = var.deploy_hub && var.enable_keycloak ? 1 : 0

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]

    command = <<-EOT
      echo "Keycloak cleanup resources will be handled by Terraform resource destruction"
      echo "Keycloak clients and realm will be deleted automatically"
    EOT
  }

  depends_on = [
    keycloak_realm.argocd,
    keycloak_openid_client.argocd,
    keycloak_openid_client.argocd_pkce
  ]
}

# =============================================================================
# SECTION 2: APPPROJECT CLEANUP
# =============================================================================

# Note: AppProject cleanup handled by namespace deletion
# Destroy provisioners cannot reference variables - see cleanup_instructions output for manual steps

# =============================================================================
# SECTION 3: RESOURCE PROXY CREDENTIALS CLEANUP
# =============================================================================

# Note: Resource proxy credentials cleaned up with namespace deletion
# Secrets and ConfigMaps in argocd namespace will be automatically removed

# =============================================================================
# SECTION 4: NAMESPACE FINALIZER CLEANUP
# =============================================================================

# Note: Namespace finalizer cleanup must be done manually
# Destroy provisioners cannot reference variables
# See cleanup_instructions output for detailed manual cleanup commands

# =============================================================================
# SECTION 5: COMPREHENSIVE CLEANUP DOCUMENTATION
# =============================================================================

output "cleanup_instructions" {
  description = "Complete cleanup instructions for all resources"
  value       = <<-EOT
╔════════════════════════════════════════════════════════════════════════════╗
║                     COMPREHENSIVE CLEANUP GUIDE                           ║
╚════════════════════════════════════════════════════════════════════════════╝

1. AUTOMATIC CLEANUP (Recommended):
   ─────────────────────────────────
   terraform destroy -auto-approve

   This will automatically remove:
   ✓ Keycloak realm and OIDC clients
   ✓ All Kubernetes resources (ArgoCD, Principal, Agents)
   ✓ All PKI certificates and secrets
   ✓ All AppProject configurations
   ✓ All resource proxy credentials
   ✓ All Ingress and LoadBalancer resources
   ✓ All namespaces and CRDs

2. MANUAL CLEANUP (If terraform destroy fails):
   ──────────────────────────────────────────────
   # Remove stuck pods/resources
   kubectl delete pods -n ${var.hub_namespace} --context ${var.hub_cluster_context} --all --grace-period=0 --force
   
   # Remove finalizers
   kubectl patch ns ${var.hub_namespace} -p '{"metadata":{"finalizers":[]}}' --type=merge --context ${var.hub_cluster_context}
   
   # Remove namespace
   kubectl delete ns ${var.hub_namespace} --context ${var.hub_cluster_context} --ignore-not-found=true
   
   # For spokes:
   for context in ${join(" ", values(var.workload_clusters))}; do
     kubectl delete ns ${var.spoke_namespace} --context $$context --ignore-not-found=true
   done

3. VERIFICATION:
   ──────────────
   # Verify Hub cleanup
   kubectl get ns --context ${var.hub_cluster_context} | grep argocd
   
   # Verify Spoke cleanup
   for context in ${join(" ", values(var.workload_clusters))}; do
     kubectl get ns --context $$context | grep argocd
   done

4. KEYCLOAK MANUAL CLEANUP (If needed):
   ───────────────────────────────────────
   # Login to Keycloak
   # Navigate to Realm: ${var.keycloak_realm}
   # Delete clients: ${var.keycloak_client_id}
   # Delete realm: ${var.keycloak_realm}

5. TERRAFORM STATE CLEANUP:
   ────────────────────────
   # Remove Terraform state files
   rm -rf terraform.tfstate terraform.tfstate.backup .terraform/
   
   # Or cleanup specific resource
   terraform state rm 'module.NAME' before destroying

╔════════════════════════════════════════════════════════════════════════════╗
║                      RESOURCE CLEANUP SUMMARY                             ║
╚════════════════════════════════════════════════════════════════════════════╝

Hub Cluster (${var.hub_cluster_context}):
  - Namespace: ${var.hub_namespace}
  - Keycloak Realm: ${var.keycloak_realm}
  - Agent Namespaces: ${join(", ", keys(var.workload_clusters))}
  - Services: argocd-server, argocd-agent-principal, argocd-agent-resource-proxy
  - Secrets: PKI certs, Keycloak client secrets, resource proxy credentials
  - ConfigMaps: argocd-cm, argocd-rbac-cm, argocd-agent-params
  - CRDs: applications.argoproj.io, appprojects.argoproj.io

Spoke Clusters:
${join("\n", [for cluster, context in var.workload_clusters : "  ${cluster} (${context}):\n    - Namespace: ${var.spoke_namespace}\n    - Services: argocd-server, argocd-repo-server, argocd-agent-agent\n    - Secrets: argocd-agent-client-tls, argocd-agent-ca"])}

IMPORTANT: Terraform destroy will remove ALL of the above resources.

EOT
}
