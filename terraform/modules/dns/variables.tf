variable "root_domain_name" {
  description = "Zone domain, must end with a period."
  type        = string
}

variable "project_id" {
  type        = string
  description = "Google Project ID"
}

variable "network_self_link" {
  type        = string
  description = "Network self link"
}

variable "name" {
  type        = string
  description = "Deployment name"
}

variable "ip_address" {
  type        = string
  description = "IP Address"
}

variable "labels" {
  description = "Map of labels for project"
  type = map(string)
  default = {}
}