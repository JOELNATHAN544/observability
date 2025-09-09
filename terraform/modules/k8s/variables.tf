variable "project_id" {
  type        = string
  description = "The ID of the project where this GKE will be created"
}

variable "region" {
  type        = string
  description = "The region where to deploy resources"
}

variable "name" {
  type        = string
  description = "Deployment name"
}

variable "machine_type" {
  type        = string
  description = "Machine type"
}

variable "network_name" {
  type = string
}

variable "sub_network_name" {
  type = string
}

variable "deletion_protection" {
  type = bool
}

variable "labels" {
  description = "Map of labels for project"
  type = map(string)
  default = {}
}