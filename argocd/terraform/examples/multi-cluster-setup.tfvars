control_plane_cluster = {
  name            = "control-plane"
  context_name    = "production-cp"
  kubeconfig_path = "~/.kube/config"
  server_address  = "argocd.prod.example.com"
  server_port     = 443
  tls_enabled     = true
}

workload_clusters = [
  {
    name              = "workload-us-east"
    context_name      = "prod-us-east"
    kubeconfig_path   = "~/.kube/config"
    principal_address = "argocd.prod.example.com"
    principal_port    = 443
    agent_name        = "agent-us-east"
    tls_enabled       = true
  },
  {
    name              = "workload-us-west"
    context_name      = "prod-us-west"
    kubeconfig_path   = "~/.kube/config"
    principal_address = "argocd.prod.example.com"
    principal_port    = 443
    agent_name        = "agent-us-west"
    tls_enabled       = true
  },
  {
    name              = "workload-eu"
    context_name      = "prod-eu"
    kubeconfig_path   = "~/.kube/config"
    principal_address = "argocd.prod.example.com"
    principal_port    = 443
    agent_name        = "agent-eu"
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
  environment  = "production"
  team         = "platform-ops"
  cost-center  = "engineering"
}

annotations_common = {
  "terraform.io/managed"      = "true"
  "owner"                      = "platform-team"
  "backup.velero.io/backup-volumes" = "data"
}
