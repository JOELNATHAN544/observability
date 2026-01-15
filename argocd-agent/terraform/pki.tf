# =============================================================================
# PKI - AUTOMATED CERTIFICATE MANAGEMENT  
# Certificates now managed via argocd-agentctl (see hub.tf null_resource)
# Manual TLS resources disabled
# =============================================================================

# =============================================================================
# HUB CA CERTIFICATE
# Self-signed CA used to sign all spoke client certificates
# =============================================================================

resource "tls_private_key" "hub_ca" {
  count = 0 # Disabled - argocd-agentctl creates this

  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "hub_ca" {
  count = 0 # Disabled - argocd-agentctl creates this

  private_key_pem = tls_private_key.hub_ca[0].private_key_pem

  subject {
    common_name  = var.ca_common_name
    organization = var.ca_organization
  }

  validity_period_hours = var.ca_validity_hours
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "digital_signature",
    "key_encipherment",
  ]
}

# Store CA certificate in Hub cluster
resource "kubernetes_secret" "hub_ca" {
  count    = 0 # Disabled - argocd-agentctl creates this
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-ca"
    namespace = var.hub_namespace
  }

  data = {
    "ca.crt"  = tls_self_signed_cert.hub_ca[0].cert_pem
    "ca.key"  = tls_private_key.hub_ca[0].private_key_pem
    "tls.crt" = tls_self_signed_cert.hub_ca[0].cert_pem
    "tls.key" = tls_private_key.hub_ca[0].private_key_pem
  }

  type = "kubernetes.io/tls"

  depends_on = [kubernetes_namespace.hub_argocd]
}

# =============================================================================
# SPOKE CLIENT CERTIFICATES
# One client certificate per spoke, signed by Hub CA
# =============================================================================

# Generate private key for spoke client
resource "tls_private_key" "spoke_client" {
  count = 0 # Disabled - argocd-agentctl creates this

  algorithm = "RSA"
  rsa_bits  = 4096
}

# Create certificate signing request for spoke
resource "tls_cert_request" "spoke_client" {
  count = 0 # Disabled - argocd-agentctl creates this

  private_key_pem = tls_private_key.spoke_client[0].private_key_pem

  subject {
    common_name  = var.spoke_id
    organization = var.ca_organization
  }
}

# Sign spoke certificate with Hub CA
resource "tls_locally_signed_cert" "spoke_client" {
  count = 0 # Disabled - argocd-agentctl creates this

  cert_request_pem   = tls_cert_request.spoke_client[0].cert_request_pem
  ca_private_key_pem = tls_private_key.hub_ca[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.hub_ca[0].cert_pem

  validity_period_hours = var.client_cert_validity_hours

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

# Store spoke client certificate in Hub cluster (for reference)
resource "kubernetes_secret" "hub_spoke_client_cert" {
  count    = 0 # Disabled - argocd-agentctl creates this
  provider = kubernetes.hub

  metadata {
    name      = "${var.spoke_id}-client-cert"
    namespace = var.hub_namespace
  }

  data = {
    "tls.crt" = tls_locally_signed_cert.spoke_client[0].cert_pem
    "tls.key" = tls_private_key.spoke_client[0].private_key_pem
    "ca.crt"  = tls_self_signed_cert.hub_ca[0].cert_pem
  }

  type = "kubernetes.io/tls"

  depends_on = [kubernetes_namespace.hub_argocd]
}

# Store spoke client certificate in Spoke cluster (for agent)
resource "kubernetes_secret" "spoke_client_cert" {
  count    = 0 # Disabled - argocd-agentctl creates this
  provider = kubernetes.spoke

  metadata {
    name      = "argocd-agent-client-cert"
    namespace = var.spoke_namespace
  }

  data = {
    "tls.crt" = tls_locally_signed_cert.spoke_client[0].cert_pem
    "tls.key" = tls_private_key.spoke_client[0].private_key_pem
    "ca.crt"  = tls_self_signed_cert.hub_ca[0].cert_pem
  }

  type = "kubernetes.io/tls"

  depends_on = [kubernetes_namespace.spoke_argocd]
}

# =============================================================================
# JWT SECRET KEY (RSA 4096-bit for ArgoCD server)
# NOTE: ArgoCD Helm chart creates argocd-secret automatically
# We generate the key for reference but don't create the secret to avoid conflicts
# =============================================================================

resource "tls_private_key" "jwt_key" {
  count = var.deploy_hub ? 1 : 0

  algorithm = "RSA"
  rsa_bits  = 4096
}

# NOTE: The argocd-secret is managed by the Helm chart
# If you need to inject a custom JWT key, use Helm values or post-deployment patching
# resource "kubernetes_secret" "argocd_jwt_secret" {
#   count    = var.deploy_hub ? 1 : 0
#   provider = kubernetes.hub
#   
#   metadata {
#     name      = "argocd-secret"
#     namespace = var.hub_namespace
#   }
#   
#   data = {
#     "server.secretkey" = tls_private_key.jwt_key[0].private_key_pem
#   }
#   
#   depends_on = [kubernetes_namespace.hub_argocd]
# }

# =============================================================================
# NAMESPACES (Dependencies for certificate secrets)
# =============================================================================

resource "kubernetes_namespace" "hub_argocd" {
  count    = var.deploy_hub ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name = var.hub_namespace
  }
}

resource "kubernetes_namespace" "spoke_argocd" {
  count    = var.deploy_spoke ? 1 : 0
  provider = kubernetes.spoke

  metadata {
    name = var.spoke_namespace
  }
}
