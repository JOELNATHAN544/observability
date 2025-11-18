resource "helm_release" "wazuh-cert-server" {
  count = 1

  name             = "wazuh-cert-server"
  namespace        = kubernetes_namespace.wazuh_namespace.metadata[0].name
  create_namespace = false

  repository = "https://adorsys-gis.github.io/wazuh-cert-oauth2"
  chart      = "wazuh-cert-server"
  version    = "0.2.25"

  values = [
    file("${path.module}/files/.wazuh-cert-oauth2/charts/wazuh-cert-server/values-pvc.yaml"),
    templatefile("${path.module}/files/cert.values.yaml", {
      cert_domain           = var.ip_addresses.cert.domain
      cert_certificate_name = local.cert_certificate_name
      cert_name             = var.ip_addresses.cert.ip_name
      openid_connect_url    = var.openid_connect_url
    })
  ]

  set {
    name  = "cert.persistence.certs.name"
    value = local.root_secret_name
  }

  cleanup_on_fail = false
  wait            = false

  depends_on = [kubernetes_namespace.wazuh_namespace]
}

resource "helm_release" "wazuh-cert-webhook" {
  count = 1

  name             = "wazuh-cert-webhook"
  namespace        = kubernetes_namespace.wazuh_namespace.metadata[0].name
  create_namespace = false

  repository = "https://adorsys-gis.github.io/wazuh-cert-oauth2"
  chart      = "wazuh-cert-webhook"
  version    = "0.2.27"

  values = [
    file("${path.module}/files/.wazuh-cert-oauth2/charts/wazuh-cert-webhook/values-pvc.yaml"),
    templatefile("${path.module}/files/cert-webhook.values.yaml", {
      openid_connect_url = var.openid_connect_url
    })
  ]

  set {
    name  = "cert.persistence.certs.name"
    value = local.root_secret_name
  }

  cleanup_on_fail = false
  wait            = false

  depends_on = [kubernetes_namespace.wazuh_namespace]
}
