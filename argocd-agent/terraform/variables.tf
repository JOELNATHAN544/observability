# =============================================================================
# DEPLOYMENT MODE CONTROL
# =============================================================================

variable "deploy_hub" {
  description = "Whether to deploy Hub (control plane) components"
  type        = bool
  default     = true
}

variable "deploy_spoke" {
  description = "Whether to deploy Spoke (workload) components"
  type        = bool
  default     = true
}

# =============================================================================
# HUB CLUSTER CONFIGURATION
# =============================================================================

variable "hub_kubeconfig_path" {
  description = "Path to kubeconfig file for Hub cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "hub_cluster_context" {
  description = "Kubernetes context for Hub cluster (leave empty to skip Hub deployment)"
  type        = string
  default     = ""
}

variable "hub_namespace" {
  description = "Namespace for ArgoCD on Hub cluster"
  type        = string
  default     = "argocd"
}

variable "hub_argocd_url" {
  description = "Public URL for ArgoCD UI on Hub (e.g., https://argocd.example.com)"
  type        = string
  default     = ""
}

variable "hub_principal_host" {
  description = "Hostname for Agent Principal gRPC endpoint (e.g., agent-principal.example.com)"
  type        = string
  default     = ""
}

# =============================================================================
# SPOKE CLUSTER CONFIGURATION
# =============================================================================

variable "spoke_kubeconfig_path" {
  description = "Path to kubeconfig file for Spoke cluster"
  type        = string
  default     = "~/.kube/config"
}

variable "spoke_cluster_context" {
  description = "Kubernetes context for Spoke cluster (leave empty to skip Spoke deployment)"
  type        = string
  default     = ""
}

variable "spoke_namespace" {
  description = "Namespace for ArgoCD on Spoke cluster"
  type        = string
  default     = "argocd"
}

variable "spoke_id" {
  description = "Unique identifier for this spoke cluster (e.g., spoke-01)"
  type        = string
  default     = "spoke-01"
}

variable "spoke_mgmt_namespace" {
  description = "Management namespace on Hub for this spoke's applications"
  type        = string
  default     = "" # Defaults to <spoke_id>-mgmt in code
}

# =============================================================================
# ARGOCD VERSION AND IMAGE SETTINGS
# =============================================================================

variable "argocd_version" {
  description = "Version of ArgoCD Helm chart"
  type        = string
  default     = "7.7.12"
}

variable "argocd_image_tag" {
  description = "ArgoCD container image tag"
  type        = string
  default     = "v2.12.6"
}

variable "skip_crds" {
  description = "Whether to skip installing ArgoCD CRDs (set to true if CRDs already exist from another installation)"
  type        = bool
  default     = false
}

# =============================================================================
# CERTIFICATE CONFIGURATION
# =============================================================================

variable "ca_common_name" {
  description = "Common Name for the Hub CA certificate"
  type        = string
  default     = "ArgoCD Agent Hub CA"
}

variable "ca_organization" {
  description = "Organization for the Hub CA certificate"
  type        = string
  default     = "ArgoCD"
}

variable "ca_validity_hours" {
  description = "Validity period for CA certificate in hours"
  type        = number
  default     = 87600 # 10 years
}

variable "client_cert_validity_hours" {
  description = "Validity period for client certificates in hours"
  type        = number
  default     = 8760 # 1 year
}

# =============================================================================
# INTEGRATION WITH EXISTING MODULES
# =============================================================================

variable "install_cert_manager" {
  description = "Whether to install cert-manager on clusters"
  type        = bool
  default     = false
}

variable "cert_manager_version" {
  description = "Version of cert-manager chart"
  type        = string
  default     = "v1.15.0"
}

variable "cert_manager_namespace" {
  description = "Namespace where cert-manager is installed"
  type        = string
  default     = "cert-manager"
}

variable "install_nginx_ingress" {
  description = "Whether to install NGINX Ingress Controller"
  type        = bool
  default     = false
}

variable "nginx_ingress_version" {
  description = "Version of ingress-nginx chart"
  type        = string
  default     = "4.10.1"
}

variable "nginx_ingress_namespace" {
  description = "Namespace where NGINX Ingress is installed"
  type        = string
  default     = "ingress-nginx"
}

variable "ingress_class_name" {
  description = "Ingress class to use for all ingress resources"
  type        = string
  default     = "nginx"
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
  default     = ""
}

variable "cert_issuer_name" {
  description = "Name of the ClusterIssuer or Issuer"
  type        = string
  default     = "letsencrypt-prod"
}

variable "cert_issuer_kind" {
  description = "Kind of Issuer (ClusterIssuer or Issuer)"
  type        = string
  default     = "ClusterIssuer"

  validation {
    condition     = contains(["ClusterIssuer", "Issuer"], var.cert_issuer_kind)
    error_message = "cert_issuer_kind must be either 'ClusterIssuer' or 'Issuer'."
  }
}

# =============================================================================
# KEYCLOAK SSO CONFIGURATION (Optional)
# =============================================================================

variable "enable_keycloak_sso" {
  description = "Whether to configure Keycloak SSO for ArgoCD"
  type        = bool
  default     = false
}

variable "keycloak_url" {
  description = "The URL of your Keycloak instance"
  type        = string
  default     = ""
}

variable "keycloak_user" {
  description = "Keycloak Admin Username"
  type        = string
  default     = "admin"
}

variable "keycloak_password" {
  description = "Keycloak Admin Password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "keycloak_client_id" {
  description = "Keycloak client ID for Terraform provider"
  type        = string
  default     = "admin-cli"
}

variable "target_realm" {
  description = "The Keycloak Realm where ArgoCD will be registered"
  type        = string
  default     = "argocd"
}

# =============================================================================
# ADVANCED CONFIGURATION
# =============================================================================

variable "enable_redis_ha" {
  description = "Enable Redis HA mode (requires 3+ replicas)"
  type        = bool
  default     = false
}

variable "redis_replica_count" {
  description = "Number of Redis replicas (only when HA enabled)"
  type        = number
  default     = 3
}

variable "principal_replica_count" {
  description = "Number of Agent Principal replicas on Hub"
  type        = number
  default     = 1
}

variable "agent_replica_count" {
  description = "Number of Agent replicas on Spoke"
  type        = number
  default     = 1
}
