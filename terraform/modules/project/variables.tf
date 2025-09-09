variable "name" {
  description = "Project Name"
  type = string
}

variable "region" {
  description = "Project region"
  type = string
}

variable "credentials" {
  type = string
  sensitive = true
}

variable "org_id" {
  description = "Project Name"
  type = string
  default = null
}

variable "project_id" {
  description = "Unique project ID"
  type = string
  default = null
}

variable "folder_id" {
  description = "Folder ID"
  type = string
  default = null
}

variable "billing_account" {
  description = "Billing account assign to project"
  type = string
  sensitive = true
}

variable "api_enabled_services" {
  description ="The list of apis necessary for the project"
  type = list(string)
  default = []
}

variable "labels" {
  description = "Map of labels for project"
  type        = map(string)
  default     = {}
}