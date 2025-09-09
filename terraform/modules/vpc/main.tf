module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 10.0"

  project_id   = var.project_id
  network_name = local.name
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name           = local.pub_sub_network_name
      subnet_ip             = "10.10.0.0/18"
      subnet_region         = var.region
      subnet_private_access = false
      auto_upgrade          = true
      auto_repair           = true
    },
    {
      subnet_name           = local.priv_sub_network_name
      subnet_ip             = "10.10.64.0/18"
      subnet_region         = var.region
      subnet_private_access = true
      auto_upgrade          = true
      auto_repair           = true
    },
  ]

  secondary_ranges = {
    ("${local.name}-subnet-01") = [
      {
        range_name    = "ip-range-pods"
        ip_cidr_range = "10.11.0.0/18"
      },
      {
        range_name    = "ip-range-services"
        ip_cidr_range = "10.11.64.0/18"
      },
    ]
  }

  auto_create_subnetworks = false
}

module "private-service-access" {
  source  = "terraform-google-modules/sql-db/google//modules/private_service_access"
  version = "~> 25.0"

  project_id      = var.project_id
  vpc_network     = module.vpc.network_name
  deletion_policy = "ABANDON"

  depends_on = [module.vpc]
}
