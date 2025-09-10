module "project" {
  source = "./modules/project"
  count  = var.create_project ? 1 : 0

  project_id           = var.project_id
  region               = var.region
  name                 = local.name
  billing_account      = var.billing_account
  org_id               = var.org_id
  api_enabled_services = var.api_enabled_services
  credentials          = var.credentials
  labels               = local.labels
  folder_id            = var.folder_id
}

module "ip" {
  source = "./modules/ip/"

  name       = local.name
  region     = var.region
  project_id = local.project_id

  depends_on = [module.project, module.vpc]
}

module "ingress" {
  source = "./modules/ingress/"

  root_dns   = var.root_domain_name
  name       = local.name
  ip_address = module.ip.address

  depends_on = [module.k8s, module.dns]
}

module "dns" {
  source = "./modules/dns/"
  count  = var.manage_dns ? 1 : 0


  project_id        = local.project_id
  name              = local.name
  network_self_link = module.vpc.network_self_link
  root_domain_name  = var.root_domain_name
  labels            = local.labels
  ip_address        = module.ip.address

  depends_on = [module.project]
}

module "k8s" {
  source = "./modules/k8s/"

  project_id          = local.project_id
  name                = local.name
  region              = var.region
  labels              = local.labels
  deletion_protection = false
  network_name        = module.vpc.network_name
  sub_network_name    = module.vpc.pub_sub_network_name
  machine_type        = var.machine_type

  depends_on = [module.project, module.vpc]
}

module "vpc" {
  source = "./modules/vpc/"

  project_id = local.project_id
  name       = local.name
  region     = var.region

  depends_on = [module.project]
}

module "storage" {
  source = "./modules/storage/"

  project_id = local.project_id
  labels     = local.labels
  name       = local.name
  names = [
    "monitoring-loki",
    "monitoring-tempo",
  ]

  depends_on = [module.project]
}

module "helm-apps" {
  source = "./modules/helm/"

  argo_hostname      = local.argo_hostname
  argo_chart_version = var.argo_chart_version
  argo_issuer        = var.argo_issuer
  argo_client_id     = var.argo_client_id
  argo_client_secret = var.argo_client_secret

  loki_bucket        = module.storage.buckets_map["monitoring-loki"].name
  loki_s3_access_key = module.storage.access_ids["monitoring-loki"]
  loki_s3_secret_key = module.storage.secrets["monitoring-loki"]

  tempo_bucket        = module.storage.buckets_map["monitoring-tempo"].name
  tempo_s3_access_key = module.storage.access_ids["monitoring-tempo"]
  tempo_s3_secret_key = module.storage.secrets["monitoring-tempo"]

  depends_on = [module.k8s, module.storage, module.dns, module.ingress]
}
