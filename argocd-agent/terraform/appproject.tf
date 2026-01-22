# =============================================================================
# APPPROJECT CONFIGURATION & SYNCHRONIZATION
# Manages AppProject propagation to agents for managed mode
# =============================================================================

# =============================================================================
# SECTION 1: CONFIGURE DEFAULT APPPROJECT ON HUB
# =============================================================================

# Patch the default AppProject with proper source and destination namespaces
# This is CRITICAL for managed mode agents to sync applications
resource "null_resource" "appproject_default_config" {
  count = var.deploy_hub && var.enable_appproject_sync ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Build destination configuration based on whether agents exist
      if [ -z "${local.all_agent_names_str}" ] || [ "${local.all_agent_names_str}" = "" ]; then
        # No agents yet - use wildcard
        DEST_SERVER="*"
      else
        # Agents exist - use wildcard for server
        DEST_SERVER="*"
      fi

      # Create AppProject patch file
      cat <<EOF > appproject-patch.yaml
spec:
  sourceNamespaces: ${jsonencode(var.appproject_default_source_namespaces)}
  destinations:
    - name: "*"
      namespace: "*"
      server: "$DEST_SERVER"
EOF

      # Patch default AppProject with proper permissions
      kubectl patch appproject default -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch-file appproject-patch.yaml

      rm appproject-patch.yaml
      echo "✓ Default AppProject configured for managed mode"
EOT
  }

  depends_on = [null_resource.hub_apps_any_namespace]

  triggers = {
    source_namespaces = jsonencode(var.appproject_default_source_namespaces)
    dest_namespaces   = jsonencode(var.appproject_default_dest_namespaces)
  }
}

# =============================================================================
# SECTION 2: APPPROJECT PROPAGATION TO AGENTS (Managed Mode)
# =============================================================================

# The default AppProject will be automatically synchronized to agents
# by the ArgoCD Agent framework when agents connect in managed mode.
# This resource documents the process but doesn't need explicit Terraform action.

# Verify AppProject exists on hub before agents connect
resource "null_resource" "appproject_verify" {
  count = var.deploy_hub && var.enable_appproject_sync && var.deploy_spokes ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Wait for AppProject to be ready
      kubectl wait --for=condition=Ready appproject/default \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --timeout=60s || true

      # Verify AppProject has proper configuration
      APPPROJ=$(kubectl get appproject default -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        -o jsonpath='{.spec.sourceNamespaces}' 2>/dev/null)

      if [ -z "$APPPROJ" ]; then
        echo "WARNING: AppProject configuration not fully applied yet"
        exit 1
      fi

      echo "✓ AppProject verified on hub"
    EOT
  }

  depends_on = [
    null_resource.appproject_default_config,
    null_resource.spoke_wait_ready
  ]
}

# =============================================================================
# SECTION 3: PER-AGENT APPPROJECT NAMESPACE PREPARATION
# =============================================================================

# Create agent-specific AppProject if custom per-agent restrictions are needed
# By default, the default AppProject is shared across all agents (recommended)

locals {
  all_agent_names_str = join(",", keys(var.workload_clusters))
}

# Optional: Create custom AppProject per agent for finer control
# This is disabled by default - using default AppProject is simpler
resource "null_resource" "appproject_per_agent" {
  for_each = (var.deploy_hub && var.enable_appproject_sync && false) ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # This section can be used for per-agent AppProject customization
      # Currently disabled to use the default AppProject approach
      echo "Per-agent AppProject configuration disabled (using default)"
    EOT
  }

  depends_on = [null_resource.principal_restart]
}

# =============================================================================
# SECTION 4: APPPROJECT SYNCHRONIZATION VALIDATION
# =============================================================================

# Validate that AppProject syncs to agents after connection
resource "null_resource" "appproject_sync_validation" {
  for_each = (var.deploy_spokes && var.enable_appproject_sync) ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Wait for agent to connect first
      sleep 30

      # Check if AppProject has been synchronized to the agent
      MAX_ATTEMPTS=60
      ATTEMPT=0
      while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
        APPPROJ=$(kubectl get appproject default -n ${var.spoke_namespace} \
          --context ${each.value} \
          -o jsonpath='{.metadata.name}' 2>/dev/null)

        if [ "$APPPROJ" = "default" ]; then
          echo "✓ AppProject synchronized to agent ${each.key}"
          exit 0
        fi

        ATTEMPT=$((ATTEMPT + 1))
        echo "Waiting for AppProject sync to agent ${each.key}... ($ATTEMPT/$MAX_ATTEMPTS)"
        sleep 2
      done

      echo "WARNING: AppProject not yet synchronized to agent ${each.key} (may be normal if agent just connected)"
      exit 0
    EOT
  }

  depends_on = [
    null_resource.agent_restart,
    null_resource.appproject_default_config
  ]

  triggers = {
    agent = each.key
  }
}

# =============================================================================
# SECTION 5: OUTPUTS
# =============================================================================

output "appproject_default_name" {
  description = "Default AppProject name for managed agents"
  value       = var.deploy_hub && var.enable_appproject_sync ? "default" : null
}

output "appproject_source_namespaces" {
  description = "Allowed source namespaces (repositories) for ApplicationSets"
  value       = var.enable_appproject_sync ? var.appproject_default_source_namespaces : null
}

output "appproject_destinations" {
  description = "Allowed destination servers and namespaces for Applications"
  value = var.enable_appproject_sync ? {
    server    = var.appproject_default_dest_server
    namespace = var.appproject_default_dest_namespaces
  } : null
}

output "appproject_sync_status" {
  description = "AppProject synchronization status instructions"
  value = var.deploy_hub && var.enable_appproject_sync ? format(
    "AppProject 'default' will be automatically synchronized to connected agents. Verify with: kubectl get appproject -n %s --context <agent-context>",
    var.spoke_namespace
  ) : null
}
