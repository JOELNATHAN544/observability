module "argo-cd" {
  source  = "blackbird-cloud/deployment/helm"
  version = "~> 1.0"

  name             = "argo-cd"
  namespace        = "argo-cd"
  create_namespace = true

  repository    = "https://argoproj.github.io/argo-helm"
  chart         = "argo-cd"
  chart_version = var.argo_chart_version

  values = [
    templatefile("${path.module}/files/argo-cd.values.yaml", {
      hostname      = var.argo_hostname
      issuer        = var.argo_issuer
      client_id     = var.argo_client_id
      client_secret = var.argo_client_secret
    })
  ]

  cleanup_on_fail = true
  wait            = true
}

module "cert_manager_issuer" {
  source  = "blackbird-cloud/deployment/helm"
  version = "~> 1.0"

  name             = "cert-manager-clusterissuer"
  namespace        = "cert-manager"
  create_namespace = false

  repository    = "https://bedag.github.io/helm-charts"
  chart         = "raw"
  chart_version = "2.0.0"

  values = [
    templatefile("${path.module}/files/cert-issuer.values.yaml", {})
  ]

  cleanup_on_fail = true
  wait            = true
}

module "monitoring-secrets" {
  source  = "blackbird-cloud/deployment/helm"
  version = "~> 1.0"

  name             = "cert-manager-clusterissuer"
  namespace        = "cert-manager"
  create_namespace = false

  repository    = "https://bedag.github.io/helm-charts"
  chart         = "raw"
  chart_version = "2.0.0"

  values = [
    templatefile("${path.module}/files/monitoring-secrets.values.yaml", {
      loki_bucket         = var.loki_bucket
      loki_s3_access_key  = var.loki_s3_access_key
      loki_s3_secret_key  = var.loki_s3_secret_key
      tempo_bucket        = var.tempo_bucket
      tempo_s3_access_key = var.tempo_s3_access_key
      tempo_s3_secret_key = var.tempo_s3_secret_key
    })
  ]

  cleanup_on_fail = true
  wait            = true
}

