variable "argo_chart_version" {
  type    = string
}

variable "argo_hostname" {
  type = string
}

variable "argo_issuer" {
  type = string
}

variable "argo_client_id" {
  type = string
  sensitive = true
}

variable "argo_client_secret" {
  type = string
  sensitive = true
}

####

variable "loki_bucket" {
  type = string
}

variable "loki_s3_access_key" {
  type = string
  sensitive = true
}

variable "loki_s3_secret_key" {
  type = string
  sensitive = true
}

####

variable "tempo_bucket" {
  type = string
}

variable "tempo_s3_access_key" {
  type = string
  sensitive = true
}

variable "tempo_s3_secret_key" {
  type = string
  sensitive = true
}

