control_plane_cluster = {
  name            = "control-plane"
  context_name    = "ha-cp"
  kubeconfig_path = "~/.kube/config"
  server_address  = "argocd-ha.example.com"
  server_port     = 443
  tls_enabled     = true
}

workload_clusters = [
  {
    name              = "workload-ha"
    context_name      = "ha-workload"
    kubeconfig_path   = "~/.kube/config"
    principal_address = "argocd-ha.example.com"
    principal_port    = 443
    agent_name        = "agent-ha"
    tls_enabled       = true
  }
]

tls_config = {
  generate_certs     = true
  cert_validity_days = 365
  tls_algorithm      = "RSA"
}

argocd_version         = "7.0.0"
argocd_agent_version   = "1.1.0"
enable_server_ui       = true
server_service_type    = "LoadBalancer"

controller_replicas    = 3
repo_server_replicas   = 3
agent_mode             = "autonomous"
create_certificate_authority = true

labels_common = {
  managed_by   = "terraform"
  application  = "argocd"
  environment  = "ha-production"
  tier         = "control-plane"
}

annotations_common = {
  "terraform.io/managed" = "true"
  "owner"                = "platform-team"
  "sla"                  = "99.9"
}
