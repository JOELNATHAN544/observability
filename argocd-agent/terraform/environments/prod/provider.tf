# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================
# Configures providers for hub and spoke clusters
# =============================================================================

provider "kubernetes" {
  alias          = "hub"
  config_path    = "~/.kube/config"
  config_context = var.hub_cluster_context
}

provider "helm" {
  alias = "hub"
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.hub_cluster_context
  }
}

# Keycloak provider supports two authentication modes:
# 1. User credentials (username/password) - for development/small teams
# 2. Client credentials (client_secret) - for production automation
provider "keycloak" {
  client_id = var.keycloak_provider_client_id
  url       = var.keycloak_url
  realm     = var.keycloak_realm

  # User credentials flow (when client_secret is empty)
  username = var.keycloak_provider_client_secret == "" ? var.keycloak_user : null
  password = var.keycloak_provider_client_secret == "" ? var.keycloak_password : null

  # Client credentials flow (when client_secret is set)
  client_secret = var.keycloak_provider_client_secret != "" ? var.keycloak_provider_client_secret : null
}

# Spoke cluster providers are configured dynamically
# Each spoke cluster context is passed through variables

# Note: Spoke cluster operations are handled via kubectl --context flags
# in null_resource provisioners to support dynamic multi-cluster management
