# =============================================================================
# SPOKE CLUSTER RESOURCES (HEADLESS MODE)
# Application controller, repo server, redis, and agent
# =============================================================================

# =============================================================================
# ARGOCD HELM RELEASE (SPOKE - HEADLESS)
# =============================================================================

resource "helm_release" "argocd_spoke" {
  count    = var.deploy_spoke ? 1 : 0
  provider = helm.spoke

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = var.spoke_namespace
  create_namespace = false # Created by pki.tf
  version          = var.argocd_version
  skip_crds        = false

  values = [
    yamlencode({
      global = {
        image = {
          tag = var.argocd_image_tag
        }
      }

      # Application Controller (runs on Spoke)
      controller = {
        replicas = 1

        # Configure to use localhost repo server and redis
        env = [
          {
            name  = "ARGOCD_APPLICATION_CONTROLLER_REPO_SERVER"
            value = "localhost:8081"
          },
          {
            name  = "ARGOCD_REDIS_SERVER"
            value = "localhost:6379"
          }
        ]
      }

      # Repo Server (localhost on Spoke)
      repoServer = {
        replicas = 1
      }

      # Redis (localhost on Spoke)
      redis = {
        enabled = true
      }

      # Server not needed on Spoke
      server = {
        replicas = 0
      }

      # ApplicationSet not needed on Spoke
      applicationset = {
        enabled = false
      }

      # Dex not needed on Spoke
      dex = {
        enabled = false
      }

      # Notifications not needed on Spoke
      notifications = {
        enabled = false
      }
    })
  ]

  depends_on = [kubernetes_namespace.spoke_argocd]
}

# =============================================================================
# AGENT CERTIFICATE GENERATION (Using argocd-agentctl)
# =============================================================================

# Generate agent certificate on Hub cluster using argocd-agentctl
resource "null_resource" "agent_cert_generation" {
  count = var.deploy_spoke ? 1 : 0

  triggers = {
    spoke_id            = var.spoke_id
    principal_context   = var.hub_cluster_context
    principal_namespace = var.hub_namespace
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Use existing agentctl from Hub deployment or install locally
      if [ -f ${path.module}/argocd-agentctl ]; then
        AGENTCTL="${path.module}/argocd-agentctl"
      elif command -v argocd-agentctl &> /dev/null; then
        AGENTCTL="argocd-agentctl"
      else
        echo "Installing argocd-agentctl to local directory..."
        VERSION="v0.5.3"
        curl -sSL -o ${path.module}/argocd-agentctl \
          "https://github.com/argoproj-labs/argocd-agent/releases/download/$${VERSION}/argocd-agentctl_linux-amd64"
        chmod +x ${path.module}/argocd-agentctl
        AGENTCTL="${path.module}/argocd-agentctl"
      fi

      echo "Using agentctl: $AGENTCTL"

      # Check if agent certificate already exists
      if kubectl get secret ${self.triggers.spoke_id}-agent-cert \
        -n ${self.triggers.principal_namespace} \
        --context ${self.triggers.principal_context} 2>/dev/null; then
        echo "Agent certificate already exists. Skipping..."
      else
        echo "Generating agent certificate for ${self.triggers.spoke_id}..."
        $AGENTCTL pki issue agent ${self.triggers.spoke_id} \
          --agent-context ${var.spoke_cluster_context} \
          --principal-context ${self.triggers.principal_context} \
          --principal-namespace ${self.triggers.principal_namespace} \
          --agent-namespace ${var.spoke_namespace}
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      kubectl delete secret ${self.triggers.spoke_id}-agent-cert \
        -n ${self.triggers.principal_namespace} \
        --context ${self.triggers.principal_context} || true
    EOT
  }

  depends_on = [null_resource.agent_pki_init]
}

# Sync agent certificate from Hub to Spoke cluster
resource "null_resource" "sync_agent_cert_to_spoke" {
  count = var.deploy_spoke ? 1 : 0

  triggers = {
    spoke_id           = var.spoke_id
    hub_context        = var.hub_cluster_context
    hub_namespace      = var.hub_namespace
    spoke_context      = var.spoke_cluster_context
    spoke_namespace    = var.spoke_namespace
    cert_generation_id = null_resource.agent_cert_generation[0].id
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Extract certificate from Hub and apply to Spoke
      kubectl get secret ${self.triggers.spoke_id}-agent-cert \
        -n ${self.triggers.hub_namespace} \
        --context ${self.triggers.hub_context} \
        -o json | \
      jq 'del(.metadata.namespace, .metadata.resourceVersion, .metadata.uid, .metadata.creationTimestamp, .metadata.managedFields)' | \
      kubectl apply -f - \
        -n ${self.triggers.spoke_namespace} \
        --context ${self.triggers.spoke_context}
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      kubectl delete secret ${self.triggers.spoke_id}-agent-cert \
        -n ${self.triggers.spoke_namespace} \
        --context ${self.triggers.spoke_context} || true
    EOT
  }

  depends_on = [
    null_resource.agent_cert_generation,
    kubernetes_namespace.spoke_argocd
  ]
}

# =============================================================================
# ARGOCD AGENT DEPLOYMENT
# =============================================================================

resource "kubernetes_deployment" "agent" {
  count    = var.deploy_spoke ? 1 : 0
  provider = kubernetes.spoke

  metadata {
    name      = "argocd-agent"
    namespace = var.spoke_namespace

    labels = {
      "app.kubernetes.io/name"      = "argocd-agent"
      "app.kubernetes.io/component" = "agent"
      "app.kubernetes.io/part-of"   = "argocd"
    }
  }

  spec {
    replicas = var.agent_replica_count

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "argocd-agent"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "argocd-agent"
          "app.kubernetes.io/component" = "agent"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.agent[0].metadata[0].name

        container {
          name  = "agent"
          image = "quay.io/argoproj/argocd:${var.argocd_image_tag}"

          command = ["/usr/local/bin/argocd-agent"]

          # Agent configuration
          env {
            name  = "ARGOCD_AGENT_SERVER"
            value = var.hub_principal_host != "" ? "${var.hub_principal_host}:8443" : ""
          }

          env {
            name  = "ARGOCD_AGENT_NAMESPACE"
            value = local.spoke_mgmt_namespace
          }

          env {
            name  = "ARGOCD_AGENT_ID"
            value = var.spoke_id
          }

          env {
            name  = "ARGOCD_AGENT_TLS_CERT"
            value = "/app/config/tls/tls.crt"
          }

          env {
            name  = "ARGOCD_AGENT_TLS_KEY"
            value = "/app/config/tls/tls.key"
          }

          env {
            name  = "ARGOCD_AGENT_CA_CERT"
            value = "/app/config/tls/ca.crt"
          }

          # Empty value enables mTLS authentication
          env {
            name  = "ARGOCD_AGENT_CREDS"
            value = ""
          }

          port {
            container_port = 8080
            name           = "metrics"
            protocol       = "TCP"
          }

          volume_mount {
            name       = "tls-certs"
            mount_path = "/app/config/tls"
            read_only  = true
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "tls-certs"

          secret {
            secret_name = "${var.spoke_id}-agent-cert"
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.argocd_spoke,
    null_resource.sync_agent_cert_to_spoke
  ]
}

# =============================================================================
# AGENT SERVICE (for metrics)
# =============================================================================

resource "kubernetes_service" "agent" {
  count    = var.deploy_spoke ? 1 : 0
  provider = kubernetes.spoke

  metadata {
    name      = "argocd-agent"
    namespace = var.spoke_namespace

    labels = {
      "app.kubernetes.io/name"      = "argocd-agent"
      "app.kubernetes.io/component" = "agent"
    }
  }

  spec {
    type = "ClusterIP"

    port {
      name        = "metrics"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }

    selector = {
      "app.kubernetes.io/name" = "argocd-agent"
    }
  }
}
