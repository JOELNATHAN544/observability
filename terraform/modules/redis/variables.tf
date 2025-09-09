variable "project_id" {
  type        = string
  description = "The ID of the project where this Redis will be created"
}

variable "region" {
  type        = string
  description = "The region where to deploy resources"
}

variable "name" {
  type        = string
  description = "The name of the project where this VPC will be created"
}

variable "authorized_network" {
  type = string
  description = "The name of the network where this network should be launched to"
}