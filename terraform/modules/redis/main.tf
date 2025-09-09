module "redis" {
  source  = "terraform-google-modules/memorystore/google"
  version = "~> 14.0"

  name                    = local.name
  region                  = var.region
  project_id              = var.project_id
  memory_size_gb          = "1"
  enable_apis             = false
  authorized_network      = var.authorized_network
  connect_mode            = "PRIVATE_SERVICE_ACCESS"
  transit_encryption_mode = "DISABLED"
}