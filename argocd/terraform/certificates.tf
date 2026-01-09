locals {
  cert_dir = "${path.module}/certs"
}

resource "local_file" "certs_directory" {
  filename = "${local.cert_dir}/.gitkeep"
  content  = ""
}

resource "tls_private_key" "ca" {
  count             = var.create_certificate_authority ? 1 : 0
  algorithm         = "RSA"
  rsa_bits          = 4096
}

resource "tls_self_signed_cert" "ca" {
  count                 = var.create_certificate_authority ? 1 : 0
  private_key_pem       = tls_private_key.ca[0].private_key_pem
  is_ca_certificate     = true
  validity_period_hours = var.tls_config.cert_validity_days * 24

  subject {
    common_name  = "Argo CD CA"
    organization = "Argo CD"
  }

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
  ]
}

resource "local_file" "ca_cert" {
  count    = var.create_certificate_authority ? 1 : 0
  filename = "${local.cert_dir}/ca.crt"
  content  = tls_self_signed_cert.ca[0].cert_pem
}

resource "local_file" "ca_key" {
  count    = var.create_certificate_authority ? 1 : 0
  filename = "${local.cert_dir}/ca.key"
  content  = tls_private_key.ca[0].private_key_pem
}

resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = var.control_plane_cluster.server_address
    organization = "Argo CD"
  }

  dns_names = [
    var.control_plane_cluster.server_address,
    "argocd-server",
    "argocd-server.${var.argocd_namespace}",
    "argocd-server.${var.argocd_namespace}.svc",
    "argocd-server.${var.argocd_namespace}.svc.cluster.local",
  ]
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem      = tls_cert_request.server.cert_request_pem
  ca_cert_pem           = var.create_certificate_authority ? tls_self_signed_cert.ca[0].cert_pem : tls_self_signed_cert.ca[0].cert_pem
  ca_private_key_pem    = var.create_certificate_authority ? tls_private_key.ca[0].private_key_pem : tls_private_key.ca[0].private_key_pem
  validity_period_hours = var.tls_config.cert_validity_days * 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
    "client_auth",
  ]
}

resource "local_file" "server_cert" {
  filename = "${local.cert_dir}/argocd-server.crt"
  content  = tls_locally_signed_cert.server.cert_pem
}

resource "local_file" "server_key" {
  filename = "${local.cert_dir}/argocd-server.key"
  content  = tls_private_key.server.private_key_pem
}

resource "tls_private_key" "agent_client" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_cert_request" "agent_client" {
  private_key_pem = tls_private_key.agent_client.private_key_pem

  subject {
    common_name  = "argocd-agent"
    organization = "Argo CD"
  }

  dns_names = [
    "argocd-agent",
  ]
}

resource "tls_locally_signed_cert" "agent_client" {
  cert_request_pem      = tls_cert_request.agent_client.cert_request_pem
  ca_cert_pem           = var.create_certificate_authority ? tls_self_signed_cert.ca[0].cert_pem : tls_self_signed_cert.ca[0].cert_pem
  ca_private_key_pem    = var.create_certificate_authority ? tls_private_key.ca[0].private_key_pem : tls_private_key.ca[0].private_key_pem
  validity_period_hours = var.tls_config.cert_validity_days * 24

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

resource "local_file" "agent_client_cert" {
  filename = "${local.cert_dir}/agent-client.crt"
  content  = tls_locally_signed_cert.agent_client.cert_pem
}

resource "local_file" "agent_client_key" {
  filename = "${local.cert_dir}/agent-client.key"
  content  = tls_private_key.agent_client.private_key_pem
}
