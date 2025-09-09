module "nginx" {
  source  = "blackbird-cloud/deployment/helm"
  version = "~> 1.0"

  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true

  repository    = "https://kubernetes.github.io/ingress-nginx"
  chart         = "ingress-nginx"
  chart_version = "4.12.1"

  values = [
    templatefile("${path.module}/files/nginx.values.yaml", {
      root_dns   = var.root_dns
      ip_address = var.ip_address
    })
  ]

  cleanup_on_fail = true
  wait            = true
}

module "cert-manager" {
  source  = "blackbird-cloud/deployment/helm"
  version = "~> 1.0"

  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true

  repository    = "https://charts.jetstack.io"
  chart         = "cert-manager"
  chart_version = "v1.16.3"

  values = [
    templatefile("${path.module}/files/cert-manager.values.yaml", {
      root_dns : var.root_dns
    })
  ]

  cleanup_on_fail = true
  wait            = true
}
