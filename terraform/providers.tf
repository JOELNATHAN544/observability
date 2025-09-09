provider "google" {
  credentials = file(var.credentials)

  region  = var.region
}

provider "google-beta" {
  credentials = file(var.credentials)

  region  = var.region
}

provider "helm" {
  kubernetes {
    host  = module.k8s.cluster_endpoint
    token = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(module.k8s.cluster_ca)
  }
}

provider "kubernetes" {
  host  = module.k8s.cluster_endpoint
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.k8s.cluster_ca)
}