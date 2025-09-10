variable "project_id" {
  type        = string
  description = "The ID of the project where this VPC will be created"
  default     = ""
}

variable "create_project" {
  type        = bool
  description = "Should we create a project?"
  default     = false
}

variable "folder_id" {
  type        = string
  description = "Folder ID in the folder in which project"
  default     = null
}

variable "manage_dns" {
  type        = bool
  description = "Set whether the DNS instances with DNS hostnames"
  default     = false
}

variable "region" {
  type        = string
  description = "The region where to deploy resources"
}

variable "name" {
  type        = string
  default     = "monitoring"
  description = "base name of this deployment"
}

variable "machine_type" {
  type        = string
  description = "Machine type"
}

variable "billing_account" {
  type        = string
  sensitive   = true
  description = "Billing account id for the project"
  default     = ""
}

variable "org_id" {
  type        = string
  description = "Google Organization ID"
  default     = null
}

variable "root_domain_name" {
  type    = string
  default = "observability.adorsys.team"
}

variable "environment" {
  type = string
}

variable "credentials" {
  type        = string
  description = "File path to the credentials file. Keep in mind that the user or service account associated to this credentials file must have the necessary permissions to create the resources defined in this module."
  sensitive   = true
}

variable "api_enabled_services" {
  description = "The list of apis necessary for the project"
  type        = list(string)
  default = [
    "compute.googleapis.com",
    "gkehub.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudkms.googleapis.com",
    "logging.googleapis.com",
    "cloudbilling.googleapis.com",
    "iam.googleapis.com",
    "admin.googleapis.com",
    "storage-api.googleapis.com",
    "monitoring.googleapis.com",
    "securitycenter.googleapis.com",
    "billingbudgets.googleapis.com",
    "vpcaccess.googleapis.com",
    "dns.googleapis.com",
    "containerregistry.googleapis.com",
    "eventarc.googleapis.com",
    "run.googleapis.com",
    "container.googleapis.com",
    "dns.googleapis.com",
    "deploymentmanager.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudbuild.googleapis.com",
    "file.googleapis.com",
    "certificatemanager.googleapis.com",
    "domains.googleapis.com",
  ]
}

variable "argo_chart_version" {
  type    = string
  default = "8.3.5"
}

variable "argo_hostname" {
  type    = string
  default = ""
}

variable "argo_issuer" {
  type = string
}

variable "argo_client_id" {
  type      = string
  sensitive = true
}

variable "argo_client_secret" {
  type      = string
  sensitive = true
}
