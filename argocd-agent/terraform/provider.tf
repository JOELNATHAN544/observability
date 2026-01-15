# =============================================================================
# TERRAFORM PROVIDER CONFIGURATION
# Multi-cluster setup with Hub (control plane) and Spoke (workload) clusters
# =============================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    keycloak = {
      source  = "mrparkers/keycloak"
      version = "~> 4.0"
    }
  }
}

# =============================================================================
# HUB CLUSTER PROVIDERS
# =============================================================================

provider "kubernetes" {
  alias          = "hub"
  config_path    = var.hub_kubeconfig_path
  config_context = var.hub_cluster_context
}

provider "helm" {
  alias = "hub"

  kubernetes {
    config_path    = var.hub_kubeconfig_path
    config_context = var.hub_cluster_context
  }
}

# =============================================================================
# SPOKE CLUSTER PROVIDERS (Dynamic)
# Note: For multiple spokes, users should configure additional providers
# or use for_each with provider aliases in calling module
# =============================================================================

provider "kubernetes" {
  alias          = "spoke"
  config_path    = var.spoke_kubeconfig_path
  config_context = var.spoke_cluster_context
}

provider "helm" {
  alias = "spoke"

  kubernetes {
    config_path    = var.spoke_kubeconfig_path
    config_context = var.spoke_cluster_context
  }
}

# =============================================================================
# KEYCLOAK PROVIDER (Optional - for SSO integration)
# =============================================================================

provider "keycloak" {
  client_id     = var.keycloak_client_id
  username      = var.keycloak_user
  password      = var.keycloak_password
  url           = var.keycloak_url
  initial_login = false
}
