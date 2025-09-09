module "gis" {
  source  = "terraform-google-modules/project-factory/google"
  version = "~> 18.0"

  name                    = var.name
  random_project_id       = var.project_id == ""
  project_id              = var.project_id
  org_id                  = var.org_id
  billing_account         = var.billing_account
  default_service_account = "keep"
  folder_id               = var.folder_id
  activate_apis           = var.api_enabled_services

  deletion_policy = "DELETE"

  labels = var.labels
}