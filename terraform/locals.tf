locals {
  name       = "${var.name}-${var.environment}"
  project_id = var.create_project ? module.project[0].project_id : var.project_id
  labels = {
    owner       = local.name,
    environment = var.environment
  }

  argo_hostname = var.argo_hostname != "" ? var.argo_hostname : "argo-cd.${var.root_domain_name}"
}
