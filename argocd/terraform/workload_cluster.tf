resource "kubernetes_namespace" "argocd_workload" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name = var.argocd_namespace
    labels = merge(
      var.labels_common,
      {
        "cluster-role" = "workload"
      }
    )
    annotations = var.annotations_common
  }
}

resource "kubernetes_secret" "argocd_agent_client_tls" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-agent-client-tls"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name
    labels = merge(
      var.labels_common,
      { "component" = "agent" }
    )
    annotations = var.annotations_common
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = tls_locally_signed_cert.agent_client.cert_pem
    "tls.key" = tls_private_key.agent_client.private_key_pem
  }

  depends_on = [
    local_file.agent_client_cert,
    local_file.agent_client_key
  ]
}

resource "kubernetes_secret" "argocd_ca_cert_workload" {
  provider = kubernetes.workload_cluster_1

  count = var.create_certificate_authority ? 1 : 0

  metadata {
    name      = "argocd-ca-cert"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name
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

resource "helm_release" "argocd_workload" {
  provider = helm.workload_cluster_1

  name             = "argocd"
  repository       = var.helm_repository_url
  chart            = "argo-cd"
  namespace        = kubernetes_namespace.argocd_workload.metadata[0].name
  create_namespace = false
  version          = var.argocd_version

  values = [
    jsonencode({
      global = {
        domain = "argocd-workload"
      }

      server = {
        replicas = 1
        service = {
          type = "ClusterIP"
        }
        tls = {
          enabled = false
        }
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }
      }

      repoServer = {
        replicas = 1
        tls = {
          enabled = false
        }
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }
      }

      controller = {
        replicas = 1
        metrics = {
          enabled = true
          serviceMonitor = {
            enabled = false
          }
        }
      }

      dex = {
        enabled = false
      }

      redis = {
        enabled = true
      }

      configs = {
        cm = {
          "server.disable.auth" = "true"
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

  depends_on = [kubernetes_namespace.argocd_workload]
}

resource "kubernetes_config_map" "argocd_agent_config" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-agent-config"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name
    labels = merge(
      var.labels_common,
      { "component" = "agent-config" }
    )
    annotations = var.annotations_common
  }

  data = {
    "server.address"       = var.workload_clusters[0].principal_address
    "server.port"          = tostring(var.workload_clusters[0].principal_port)
    "server.tls.enabled"   = tostring(var.workload_clusters[0].tls_enabled)
    "agent.name"           = var.workload_clusters[0].agent_name
    "agent.mode"           = var.agent_mode
    "agent.tls.enabled"    = tostring(var.workload_clusters[0].tls_enabled)
    "agent.tls.cert.path"  = "/etc/agent/tls/tls.crt"
    "agent.tls.key.path"   = "/etc/agent/tls/tls.key"
    "agent.tls.ca.path"    = "/etc/agent/ca/ca.crt"
  }

  depends_on = [kubernetes_namespace.argocd_workload]
}

resource "kubernetes_service_account" "argocd_agent" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-agent"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name
    labels = merge(
      var.labels_common,
      { "component" = "agent" }
    )
    annotations = var.annotations_common
  }

  depends_on = [kubernetes_namespace.argocd_workload]
}

resource "kubernetes_cluster_role" "argocd_agent" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name = "argocd-agent"
    labels = merge(
      var.labels_common,
      { "component" = "agent" }
    )
    annotations = var.annotations_common
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }

  rule {
    non_resource_urls = ["*"]
    verbs             = ["*"]
  }
}

resource "kubernetes_cluster_role_binding" "argocd_agent" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name = "argocd-agent"
    labels = merge(
      var.labels_common,
      { "component" = "agent" }
    )
    annotations = var.annotations_common
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.argocd_agent.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.argocd_agent.metadata[0].name
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name
  }

  depends_on = [kubernetes_cluster_role.argocd_agent]
}

resource "kubernetes_deployment" "argocd_agent" {
  provider = kubernetes.workload_cluster_1

  metadata {
    name      = "argocd-agent"
    namespace = kubernetes_namespace.argocd_workload.metadata[0].name
    labels = merge(
      var.labels_common,
      { "component" = "agent" }
    )
    annotations = var.annotations_common
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app       = "argocd-agent"
        component = "agent"
      }
    }

    template {
      metadata {
        labels = merge(
          var.labels_common,
          {
            app       = "argocd-agent"
            component = "agent"
          }
        )
        annotations = var.annotations_common
      }

      spec {
        service_account_name = kubernetes_service_account.argocd_agent.metadata[0].name

        container {
          name  = "agent"
          image = "ghcr.io/argoproj-labs/argocd-agent:latest"
          image_pull_policy = "IfNotPresent"

          port {
            name           = "metrics"
            container_port = 8080
            protocol       = "TCP"
          }

          env {
            name  = "AGENT_NAME"
            value = var.workload_clusters[0].agent_name
          }

          env {
            name  = "ARGOCD_SERVER_ADDRESS"
            value = var.workload_clusters[0].principal_address
          }

          env {
            name  = "ARGOCD_SERVER_PORT"
            value = tostring(var.workload_clusters[0].principal_port)
          }

          env {
            name  = "ARGOCD_AGENT_TLS_ENABLED"
            value = tostring(var.workload_clusters[0].tls_enabled)
          }

          env {
            name  = "ARGOCD_AGENT_MODE"
            value = var.agent_mode
          }

          dynamic "env" {
            for_each = var.workload_clusters[0].tls_enabled ? [1] : []
            content {
              name  = "ARGOCD_AGENT_TLS_CERT_FILE"
              value = "/etc/agent/tls/tls.crt"
            }
          }

          dynamic "env" {
            for_each = var.workload_clusters[0].tls_enabled ? [1] : []
            content {
              name  = "ARGOCD_AGENT_TLS_KEY_FILE"
              value = "/etc/agent/tls/tls.key"
            }
          }

          dynamic "env" {
            for_each = var.workload_clusters[0].tls_enabled ? [1] : []
            content {
              name  = "ARGOCD_AGENT_TLS_CA_FILE"
              value = "/etc/agent/ca/ca.crt"
            }
          }

          volume_mount {
            name       = "agent-tls"
            mount_path = "/etc/agent/tls"
            read_only  = true
          }

          volume_mount {
            name       = "agent-ca"
            mount_path = "/etc/agent/ca"
            read_only  = true
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/agent/config"
            read_only  = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "metrics"
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = "metrics"
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            failure_threshold     = 3
          }

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "agent-tls"
          secret {
            secret_name = kubernetes_secret.argocd_agent_client_tls.metadata[0].name
          }
        }

        volume {
          name = "agent-ca"
          secret {
            secret_name = var.create_certificate_authority ? kubernetes_secret.argocd_ca_cert_workload[0].metadata[0].name : "argocd-ca-cert"
          }
        }

        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map.argocd_agent_config.metadata[0].name
          }
        }

        security_context {
          fsGroup = 1000
        }
      }
    }
  }

  depends_on = [
    kubernetes_namespace.argocd_workload,
    kubernetes_secret.argocd_agent_client_tls,
    kubernetes_config_map.argocd_agent_config,
    kubernetes_service_account.argocd_agent
  ]
}
