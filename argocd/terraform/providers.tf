provider "kubernetes" {
  alias            = "control_plane"
  config_path      = abspath(pathexpand(var.control_plane_cluster.kubeconfig_path))
  config_context   = var.control_plane_cluster.context_name
}

provider "helm" {
  alias = "control_plane"
  kubernetes {
    config_path    = abspath(pathexpand(var.control_plane_cluster.kubeconfig_path))
    config_context = var.control_plane_cluster.context_name
  }
}

# FIXED: Added insecure = true to skip TLS verification for workload cluster
provider "kubernetes" {
  alias            = "workload_cluster_1"
  config_path      = abspath(pathexpand(var.workload_clusters[0].kubeconfig_path))
  config_context   = var.workload_clusters[0].context_name
  insecure         = true  # Skip TLS certificate verification
}

provider "helm" {
  alias = "workload_cluster_1"
  kubernetes {
    config_path    = abspath(pathexpand(var.workload_clusters[0].kubeconfig_path))
    config_context = var.workload_clusters[0].context_name
    insecure       = true  # Skip TLS certificate verification
  }
}

provider "tls" {}
provider "local" {}
