# =============================================================================
# ARGOCD HUB-AND-SPOKE ARCHITECTURE
# Main orchestration file - All resources are defined in separate files:
# - pki.tf: Certificate management (Hub CA, spoke client certs, JWT keys)
# - rbac.tf: RBAC configurations for Principal and Agent
# - hub.tf: Hub cluster resources (server, principal, redis, applicationset)
# - spoke.tf: Spoke cluster resources (controller, repo-server, redis, agent)
# - provider.tf: Multi-cluster provider configuration
# - variables.tf: Input variables
# - outputs.tf: Output values
# =============================================================================

# This file serves as the entry point and documentation.
# All actual resources are organized in domain-specific files.

# =============================================================================
# LOCAL VARIABLES
# =============================================================================

locals {
  # Spoke management namespace defaults to <spoke-id>-mgmt if not specified
  spoke_mgmt_namespace = var.spoke_mgmt_namespace != "" ? var.spoke_mgmt_namespace : "${var.spoke_id}-mgmt"

  # Deployment mode for logging
  deployment_mode = var.deploy_hub && var.deploy_spoke ? "full" : (var.deploy_hub ? "hub-only" : (var.deploy_spoke ? "spoke-only" : "none"))
}

# =============================================================================
# DEPLOYMENT VALIDATION
# =============================================================================

# Ensure at least one deployment mode is enabled
resource "null_resource" "validate_deployment_mode" {
  lifecycle {
    precondition {
      condition     = var.deploy_hub || var.deploy_spoke
      error_message = "At least one of deploy_hub or deploy_spoke must be true."
    }
  }
}

# Validate Hub configuration if Hub deployment is enabled
resource "null_resource" "validate_hub_config" {
  count = var.deploy_hub ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.hub_cluster_context != ""
      error_message = "hub_cluster_context must be set when deploy_hub is true."
    }

    precondition {
      condition     = var.hub_argocd_url != "" || !var.deploy_spoke
      error_message = "hub_argocd_url should be set when deploying Hub with Spoke."
    }

    precondition {
      condition     = var.hub_principal_host != "" || !var.deploy_spoke
      error_message = "hub_principal_host must be set when deploying both Hub and Spoke."
    }
  }
}

# Validate Spoke configuration if Spoke deployment is enabled
resource "null_resource" "validate_spoke_config" {
  count = var.deploy_spoke ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.spoke_cluster_context != ""
      error_message = "spoke_cluster_context must be set when deploy_spoke is true."
    }

    precondition {
      condition     = var.spoke_id != ""
      error_message = "spoke_id must be set when deploy_spoke is true."
    }
  }
}

# Validate certificate configuration for full deployment
resource "null_resource" "validate_certificate_config" {
  count = var.deploy_hub && var.deploy_spoke ? 1 : 0

  lifecycle {
    precondition {
      condition     = var.hub_principal_host != ""
      error_message = "hub_principal_host is required for Agent to connect to Principal."
    }
  }
}
