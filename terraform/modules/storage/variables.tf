variable "project_id" {
  type        = string
  description = "Google Project ID"
}

variable "name" {
  type        = string
}

variable "labels" {
  description = "Map of labels for project"
  type = map(string)
  default = {}
}

variable "names" {
  type = list(string)
  description = "List of names for the project"
}