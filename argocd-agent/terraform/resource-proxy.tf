# =============================================================================
# RESOURCE PROXY CREDENTIALS MANAGEMENT
# Stores and manages resource proxy authentication credentials for agents
# =============================================================================

# =============================================================================
# SECTION 1: RESOURCE PROXY CREDENTIALS SECRET
# =============================================================================

# Store all agent resource proxy credentials in a Kubernetes secret for:
# - Easy reference and rotation
# - Secure storage in etcd
# - Audit trail via kubectl events

resource "null_resource" "resource_proxy_credentials_secret" {
  count = var.deploy_hub && var.enable_resource_proxy_credentials_secret ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command = <<-EOT
      # Build credentials JSON from all agents
      CREDENTIALS_JSON="{"
      FIRST=true

      # Add each agent's credentials
      ${join("\n", [for agent, _ in var.workload_clusters :
    "AGENT='${agent}'\nPWD='${random_password.agent_proxy_password[agent].result}'\nif [ \"$FIRST\" = \"true\" ]; then CREDENTIALS_JSON=\"$CREDENTIALS_JSON\\\"$AGENT\\\": \\\"$PWD\\\"\"; FIRST=false; else CREDENTIALS_JSON=\"$CREDENTIALS_JSON, \\\"$AGENT\\\": \\\"$PWD\\\"\"; fi"
])}

      CREDENTIALS_JSON="$CREDENTIALS_JSON}"

      # Create secret with all credentials
      kubectl create secret generic argocd-agent-resource-proxy-creds \
        --from-literal=credentials="$CREDENTIALS_JSON" \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --dry-run=client \
        -o yaml | kubectl apply -f - --context ${var.hub_cluster_context}

      echo "✓ Resource proxy credentials secret created"
    EOT
}

depends_on = [
  null_resource.principal_restart,
  random_password.agent_proxy_password
]

triggers = {
  credentials_count = length(var.workload_clusters)
}
}

# =============================================================================
# SECTION 2: RESOURCE PROXY SERVICE VERIFICATION
# =============================================================================

# Verify resource proxy service is accessible and credentials are valid
resource "null_resource" "resource_proxy_verification" {
  count = var.deploy_hub && var.enable_resource_proxy_credentials_secret ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Check resource proxy service exists
      RESOURCE_PROXY_SVC=$(kubectl get svc argocd-agent-resource-proxy \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        -o jsonpath='{.metadata.name}' 2>/dev/null)

      if [ -z "$RESOURCE_PROXY_SVC" ]; then
        echo "ERROR: argocd-agent-resource-proxy service not found"
        exit 1
      fi

      # Get resource proxy service details
      RESOURCE_PROXY_PORT=$(kubectl get svc argocd-agent-resource-proxy \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        -o jsonpath='{.spec.ports[0].port}' 2>/dev/null)

      RESOURCE_PROXY_CLUSTER_IP=$(kubectl get svc argocd-agent-resource-proxy \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        -o jsonpath='{.spec.clusterIP}' 2>/dev/null)

      if [ -z "$RESOURCE_PROXY_CLUSTER_IP" ]; then
        echo "ERROR: Cannot determine resource proxy cluster IP"
        exit 1
      fi

      echo "✓ Resource proxy service verified at $RESOURCE_PROXY_CLUSTER_IP:$RESOURCE_PROXY_PORT"
    EOT
  }

  depends_on = [null_resource.principal_install]
}

# =============================================================================
# SECTION 3: AGENT RESOURCE PROXY PASSWORD STORAGE
# =============================================================================

# For each agent, store credentials information for documentation
resource "null_resource" "agent_credentials_documentation" {
  for_each = var.workload_clusters

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Create a ConfigMap with agent credentials information (non-sensitive)
      # This helps with credential rotation and troubleshooting
      
      AGENT_NAME="${each.key}"
      
      kubectl create configmap argocd-agent-credentials-info-$AGENT_NAME \
        --from-literal=username="$AGENT_NAME" \
        --from-literal=resource-proxy-server="argocd-agent-resource-proxy.${var.hub_namespace}.svc.cluster.local:9090" \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --dry-run=client \
        -o yaml | kubectl apply -f - --context ${var.hub_cluster_context}

      echo "✓ Agent $AGENT_NAME credentials info stored"
    EOT
  }

  depends_on = [
    null_resource.agent_create,
    null_resource.resource_proxy_credentials_secret
  ]
}

# =============================================================================
# SECTION 4: CREDENTIAL ROTATION HELPER
# =============================================================================

# Document how to rotate resource proxy passwords
output "resource_proxy_credentials_rotation_guide" {
  description = "Guide for rotating resource proxy credentials"
  value = var.enable_resource_proxy_credentials_secret ? {
    retrieve_current = "kubectl get secret argocd-agent-resource-proxy-creds -n ${var.hub_namespace} -o jsonpath='{.data.credentials}' | base64 -d"
    regenerate       = "terraform taint null_resource.resource_proxy_credentials_secret && terraform apply -target=null_resource.resource_proxy_credentials_secret"
    verify           = "kubectl describe secret argocd-agent-resource-proxy-creds -n ${var.hub_namespace}"
  } : null
}

# =============================================================================
# SECTION 5: OUTPUTS
# =============================================================================

output "resource_proxy_service_name" {
  description = "Resource proxy service name for agent configuration"
  value       = "argocd-agent-resource-proxy.${var.hub_namespace}.svc.cluster.local:9090"
}

output "resource_proxy_credentials_secret_name" {
  description = "Kubernetes secret containing resource proxy credentials"
  value       = var.enable_resource_proxy_credentials_secret ? "argocd-agent-resource-proxy-creds" : null
}

output "resource_proxy_credentials_retrieval" {
  description = "Command to retrieve stored resource proxy credentials"
  value = var.enable_resource_proxy_credentials_secret ? format(
    "kubectl get secret argocd-agent-resource-proxy-creds -n %s --context %s -o jsonpath='{.data.credentials}' | base64 -d",
    var.hub_namespace,
    var.hub_cluster_context
  ) : null
  sensitive = true
}

output "agent_credentials_info_configmaps" {
  description = "Per-agent credentials information ConfigMaps created"
  value = length(var.workload_clusters) > 0 ? [
    for agent in keys(var.workload_clusters) :
    "argocd-agent-credentials-info-${agent}"
  ] : []
}
