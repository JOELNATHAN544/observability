module "gcs_buckets" {
  source     = "terraform-google-modules/cloud-storage/google"
  version    = "~> 10.0"
  project_id = var.project_id
  names      = var.names
  prefix     = local.name

  labels                = var.labels
  set_hmac_access       = true
  hmac_service_accounts = {
    for key in module.service_accounts.emails_list : key => "ACTIVE"
  }
}

module "service_accounts" {
  source     = "terraform-google-modules/service-accounts/google"
  version    = "~> 4.0"
  project_id = var.project_id
  prefix     = var.name
  names      = var.names
  project_roles = [
    "${var.project_id}=>roles/viewer",
    "${var.project_id}=>roles/storage.admin",
  ]
}