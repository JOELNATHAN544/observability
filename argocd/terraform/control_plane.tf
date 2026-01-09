resource "kubernetes_namespace" "argocd_control_plane" {
  provider = kubernetes.control_plane

  metadata {
    name = var.argocd_namespace
    labels = merge(
      var.labels_common,
      {
        "cluster-role" = "control-plane"
      }
    )
    annotations = var.annotations_common
  }
}

resource "kubernetes_secret" "argocd_server_tls_cp" {
  provider = kubernetes.control_plane

  metadata {
    name      = "argocd-server-tls"
    namespace = kubernetes_namespace.argocd_control_plane.metadata[0].name
    labels = merge(
      var.labels_common,
      { "component" = "server" }
    )
    annotations = var.annotations_common
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_locally_signed_cert.server.cert_pem
    "tls.key" = tls_private_key.server.private_key_pem
  }

  depends_on = [
    local_file.server_cert,
    local_file.server_key
  ]
}

resource "kubernetes_secret" "argocd_ca_cert_cp" {
  provider = kubernetes.control_plane

  count = var.create_certificate_authority ? 1 : 0

  metadata {
    name      = "argocd-ca-cert"
    namespace = kubernetes_namespace.argocd_control_plane.metadata[0].name
    labels = merge(
      var.labels_common,
      { "component" = "ca" }
    )
    annotations = var.annotations_common
  }

  type = "Opaque"

  data = {
    "ca.crt" = tls_self_signed_cert.ca[0].cert_pem
  }

  depends_on = [local_file.ca_cert]
}

resource "helm_release" "argocd_control_plane" {
  provider = helm.control_plane

  name             = "argocd"
  repository       = var.helm_repository_url
  chart            = "argo-cd"
  namespace        = kubernetes_namespace.argocd_control_plane.metadata[0].name
  create_namespace = false
  version          = var.argocd_version

  values = [
    jsonencode({
      global = {
        domain = var.control_plane_cluster.server_address
      }

      server = {
        service = {
          type = var.server_service_type
        }
        tls = {
          enabled = var.control_plane_cluster.tls_enabled
          certSecret = {
            caSecret = var.create_certificate_authority ? "argocd-ca-cert" : ""
            certName = "tls.crt"
            keyName  = "tls.key"
            caName   = "ca.crt"
          }
        }
        extraArgs = [
          "--insecure=false",
        ]
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }
      }

      repoServer = {
        replicas = var.repo_server_replicas
        tls = {
          enabled = var.control_plane_cluster.tls_enabled
          strict  = true
        }
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }
      }

      controller = {
        replicas = var.controller_replicas
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }
      }

      dex = {
        enabled = true
      }

      redis = {
        enabled = true
      }

      configs = {
        cm = {
          "server.disable.auth" = "false"
          "admin.enabled"        = "true"
        }
      }

      rbac = {
        create = true
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "500m"
          memory = "512Mi"
        }
      }

      persistence = {
        enabled = true
        size    = "10Gi"
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd_control_plane,
    kubernetes_secret.argocd_server_tls_cp,
    kubernetes_secret.argocd_ca_cert_cp
  ]
}

resource "kubernetes_service" "argocd_server_grpc_cp" {
  provider = kubernetes.control_plane

  metadata {
    name      = "argocd-server-grpc"
    namespace = kubernetes_namespace.argocd_control_plane.metadata[0].name
    labels = merge(
      var.labels_common,
      { "component" = "server-grpc" }
    )
    annotations = merge(
      var.annotations_common,
      {
        "description" = "gRPC service for Argo CD agent communication with mTLS"
      }
    )
  }

  spec {
    type = "ClusterIP"

    port {
      name        = "grpc"
      port        = var.control_plane_cluster.server_port
      target_port = 8080
      protocol    = "TCP"
    }

    selector = {
      "app.kubernetes.io/name" = "argocd-server"
    }
  }

  depends_on = [helm_release.argocd_control_plane]
}

resource "kubernetes_service" "argocd_principal_external_cp" {
  provider = kubernetes.control_plane

  metadata {
    name      = "argocd-principal"
    namespace = kubernetes_namespace.argocd_control_plane.metadata[0].name
    labels = merge(
      var.labels_common,
      { "component" = "principal" }
    )
    annotations = var.annotations_common
  }

  spec {
    type = var.server_service_type

    port {
      name        = "http"
      port        = 80
      target_port = 8080
      protocol    = "TCP"
    }

    port {
      name        = "https"
      port        = 443
      target_port = 8443
      protocol    = "TCP"
    }

    selector = {
      "app.kubernetes.io/name" = "argocd-server"
    }
  }

  depends_on = [helm_release.argocd_control_plane]
}

resource "kubernetes_config_map" "argocd_principal_config_cp" {
  provider = kubernetes.control_plane

  metadata {
    name      = "argocd-principal-config"
    namespace = kubernetes_namespace.argocd_control_plane.metadata[0].name
    labels = merge(
      var.labels_common,
      { "component" = "principal-config" }
    )
    annotations = var.annotations_common
  }

  data = {
    "principal.address"                = var.control_plane_cluster.server_address
    "principal.port"                   = tostring(var.control_plane_cluster.server_port)
    "principal.tls.enabled"            = tostring(var.control_plane_cluster.tls_enabled)
    "principal.tls.insecure_skip_verify" = tostring(!var.control_plane_cluster.tls_enabled)
    "principal.mode"                   = "principal"
  }

  depends_on = [kubernetes_namespace.argocd_control_plane]
}
