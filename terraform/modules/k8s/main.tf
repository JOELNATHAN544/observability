module "gke" {
  source  = "terraform-google-modules/kubernetes-engine/google"
  version = "~> 36.0"

  project_id                  = var.project_id
  name                        = local.name
  regional                    = true
  region                      = var.region
  network                     = var.network_name
  subnetwork                  = var.sub_network_name
  service_account_name        = local.name
  enable_cost_allocation      = true
  fleet_project               = var.project_id
  deletion_protection         = var.deletion_protection
  cluster_resource_labels     = var.labels
  ip_range_pods               = "ip-range-pods"
  ip_range_services           = "ip-range-services"
  http_load_balancing         = true
  horizontal_pod_autoscaling  = true
  enable_secret_manager_addon = true
  
  node_pools = [
    {
      name               = "pool-01"
      autoscaling        = true
      auto_upgrade       = true
      min_count          = 1
      max_count          = 4
      machine_type       = var.machine_type
      spot               = true
    }
  ]
}