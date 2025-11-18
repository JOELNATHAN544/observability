locals {
  name       = "${var.name}-${var.environment}"
  project_id = var.create_project ? module.project[0].project_id : var.project_id
  labels = {
    owner       = local.name,
    environment = var.environment
  }

  wazuh_domains = {
    cert      = { domain = "siem-cert.${var.root_domain_name}", regional = false },
    dashboard = { domain = "siem.${var.root_domain_name}", regional = false },
    manager   = { domain = "siem-events.${var.root_domain_name}", regional = true }
  }
}
