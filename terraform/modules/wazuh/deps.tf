resource "helm_release" "other_resources" {
  count            = 1
  name             = "other-resources"
  namespace        = kubernetes_namespace.wazuh_namespace.metadata[0].name
  create_namespace = false

  repository = "https://bedag.github.io/helm-charts"
  chart      = "raw"
  version    = "2.0.0"

  values = [templatefile("${path.module}/files/resources.yaml", {
    ns                         = kubernetes_namespace.wazuh_namespace.metadata[0].name
    dashboard_certificate_name = local.dashboard_certificate_name
    dashboard_domain           = var.ip_addresses.dashboard.domain
    manager_certificate_name   = local.manager_certificate_name
    manager_domain             = var.ip_addresses.manager.domain
    cert_certificate_name      = local.cert_certificate_name
    cert_domain                = var.ip_addresses.cert.domain
  })]

  cleanup_on_fail = false
  wait            = false
}
