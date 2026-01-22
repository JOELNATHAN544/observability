# =============================================================================
# PROVIDER CONFIGURATION
# =============================================================================

provider "kubernetes" {
  alias          = "hub"
  config_path    = "~/.kube/config"
  config_context = var.hub_cluster_context
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = var.hub_cluster_context
  }
}

provider "keycloak" {
  client_id = "admin-cli"
  url       = var.keycloak_url
  username  = var.keycloak_user
  password  = var.keycloak_password
}

# Note: Spoke cluster operations are handled via kubectl --context flags
# in null_resource provisioners to support dynamic multi-cluster management
