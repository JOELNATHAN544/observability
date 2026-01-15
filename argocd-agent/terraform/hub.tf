# =============================================================================
# HUB CLUSTER RESOURCES
# Control plane with argocd-server, agent-principal, redis, applicationset
# =============================================================================

# =============================================================================
# INTEGRATION WITH EXISTING MODULES
# =============================================================================

# Cert-Manager Module (if enabled)
module "hub_cert_manager" {
  count  = var.deploy_hub && var.install_cert_manager ? 1 : 0
  source = "../../cert-manager/terraform"

  providers = {
    kubernetes = kubernetes.hub
    helm       = helm.hub
  }

  install_cert_manager = true
  cert_manager_version = var.cert_manager_version
  release_name         = "cert-manager"
  namespace            = var.cert_manager_namespace
  letsencrypt_email    = var.letsencrypt_email
  cert_issuer_name     = var.cert_issuer_name
  cert_issuer_kind     = var.cert_issuer_kind
  issuer_namespace     = var.hub_namespace
  ingress_class_name   = var.ingress_class_name
}

# Ingress Controller Module (if enabled)
module "hub_ingress_nginx" {
  count  = var.deploy_hub && var.install_nginx_ingress ? 1 : 0
  source = "../../ingress-controller/terraform"

  providers = {
    kubernetes = kubernetes.hub
    helm       = helm.hub
  }

  install_nginx_ingress = true
  nginx_ingress_version = var.nginx_ingress_version
  release_name          = "nginx-ingress-hub"
  namespace             = var.nginx_ingress_namespace
  ingress_class_name    = var.ingress_class_name
}

# =============================================================================
# ARGOCD HELM RELEASE (HUB)
# =============================================================================

resource "helm_release" "argocd_hub" {
  count    = var.deploy_hub ? 1 : 0
  provider = helm.hub

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = var.hub_namespace
  create_namespace = false # Created by pki.tf
  version          = var.argocd_version
  skip_crds        = var.skip_crds

  values = [
    yamlencode({
      global = {
        image = {
          tag = var.argocd_image_tag
        }
      }

      # Disable application controller on Hub
      controller = {
        replicas = 0
      }

      # ArgoCD Server configuration
      server = {
        replicas = 1
        config = {
          url = var.hub_argocd_url != "" ? var.hub_argocd_url : null

          # Agent Principal configuration
          "agent.principal.enabled" = "true"
        }

        # Optional: Keycloak SSO integration
        configEnabled = var.enable_keycloak_sso
      }

      # Redis configuration
      redis = {
        enabled = true
        metrics = {
          enabled = true
        }
      }

      # Redis HA (if enabled)
      redis-ha = {
        enabled  = var.enable_redis_ha
        replicas = var.enable_redis_ha ? var.redis_replica_count : null
      }

      # ApplicationSet
      applicationset = {
        enabled  = true
        replicas = 1
      }

      # Repo server not needed on Hub
      repoServer = {
        replicas = 0
      }

      # Dex (disable if using Keycloak)
      dex = {
        enabled = !var.enable_keycloak_sso
      }
    })
  ]

  depends_on = [
    kubernetes_namespace.hub_argocd
  ]
}

# =============================================================================
# AGENT PRINCIPAL PKI INITIALIZATION
# Uses argocd-agentctl to generate required certificates and JWT keys
# =============================================================================

# PKI and JWT initialization using argocd-agentctl
resource "null_resource" "agent_pki_init" {
  count = var.deploy_hub || var.deploy_spoke ? 1 : 0

  triggers = {
    # Re-run if cluster context or namespace changes
    cluster_context = var.hub_cluster_context
    namespace       = var.hub_namespace
    # Force re-run if this changes
    force_update = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Ensure argocd-agentctl is available locally
      if ! command -v argocd-agentctl &> /dev/null; then
        echo "Installing argocd-agentctl to local directory..."
        VERSION="v0.5.3"
        curl -sSL -o ${path.module}/argocd-agentctl \
          "https://github.com/argoproj-labs/argocd-agent/releases/download/$${VERSION}/argocd-agentctl_linux-amd64"
        chmod +x ${path.module}/argocd-agentctl
        AGENTCTL="${path.module}/argocd-agentctl"
      else
        AGENTCTL="argocd-agentctl"
      fi

      echo "Using agentctl: $AGENTCTL"

      # Check if PKI already exists, if so skip initialization
      if kubectl get secret argocd-agent-ca -n ${self.triggers.namespace} --context ${self.triggers.cluster_context} 2>/dev/null; then
        echo "PKI already initialized. Skipping..."
      else
        echo "Initializing PKI..."
        $AGENTCTL pki init \
          --principal-context ${self.triggers.cluster_context} \
          --principal-namespace ${self.triggers.namespace}
      fi

      # Issue principal TLS certificate
      if kubectl get secret argocd-agent-principal-tls -n ${self.triggers.namespace} --context ${self.triggers.cluster_context} 2>/dev/null; then
        echo "Principal TLS cert already exists. Skipping..."
      else
        echo "Issuing Principal TLS certificate..."
        $AGENTCTL pki issue principal \
          --principal-context ${self.triggers.cluster_context} \
          --principal-namespace ${self.triggers.namespace}
      fi

      # Issue resource proxy TLS certificate
      if kubectl get secret argocd-agent-resource-proxy-tls -n ${self.triggers.namespace} --context ${self.triggers.cluster_context} 2>/dev/null; then
        echo "Resource proxy TLS cert already exists. Skipping..."
      else
        echo "Issuing resource proxy TLS certificate..."
        $AGENTCTL pki issue resource-proxy \
          --principal-context ${self.triggers.cluster_context} \
          --principal-namespace ${self.triggers.namespace} \
          --dns argocd-agent-resource-proxy.${self.triggers.namespace}.svc.cluster.local
      fi

      # Create JWT signing key
      if kubectl get secret argocd-agent-jwt -n ${self.triggers.namespace} --context ${self.triggers.cluster_context} 2>/dev/null; then
        echo "JWT key already exists. Skipping..."
      else
        echo "Creating JWT signing key..."
        $AGENTCTL jwt create-key \
          --principal-context ${self.triggers.cluster_context} \
          --principal-namespace ${self.triggers.namespace}
      fi
    EOT
  }

  depends_on = [
    helm_release.argocd_hub,
    kubernetes_namespace.hub_argocd
  ]
}

# =============================================================================
# AGENT PRINCIPAL DEPLOYMENT (via Kustomize)
# Official ArgoCD Agent Principal manifests
# =============================================================================

resource "null_resource" "agent_principal_install" {
  count = var.deploy_hub ? 1 : 0

  triggers = {
    pki_init        = null_resource.agent_pki_init[0].id
    namespace       = var.hub_namespace
    cluster_context = var.hub_cluster_context
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl apply -n ${self.triggers.namespace} --context ${self.triggers.cluster_context} \
        -k 'https://github.com/argoproj-labs/argocd-agent/install/kubernetes/principal?ref=v0.4.1'
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      kubectl delete -n ${self.triggers.namespace} --context ${self.triggers.cluster_context} \
        -k 'https://github.com/argoproj-labs/argocd-agent/install/kubernetes/principal?ref=v0.4.1' || true
    EOT
  }

  depends_on = [null_resource.agent_pki_init]
}

# Placeholder for the old manual deployment - kept for reference but not used
# We now use the official kustomize manifests above
resource "kubernetes_deployment" "agent_principal_manual" {
  count    = 0 # Disabled - using kustomize instead
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-principal-manual"
    namespace = var.hub_namespace

    labels = {
      "app.kubernetes.io/name"      = "argocd-agent-principal"
      "app.kubernetes.io/component" = "agent-principal"
      "app.kubernetes.io/part-of"   = "argocd"
    }
  }

  spec {
    replicas = var.principal_replica_count

    selector {
      match_labels = {
        "app.kubernetes.io/name" = "argocd-agent-principal"
      }
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name"      = "argocd-agent-principal"
          "app.kubernetes.io/component" = "agent-principal"
        }
      }

      spec {
        service_account_name = "argocd-agent-principal" # Created by kustomize

        container {
          name  = "principal"
          image = "quay.io/argoproj/argocd:${var.argocd_image_tag}"

          command = ["/usr/local/bin/argocd-agent-principal"]

          env {
            name  = "ARGOCD_AGENT_PRINCIPAL_REDIS_ADDRESS"
            value = "argocd-redis:6379"
          }

          env {
            name  = "ARGOCD_AGENT_PRINCIPAL_NAMESPACE"
            value = var.hub_namespace
          }

          port {
            container_port = 8443
            name           = "grpc"
            protocol       = "TCP"
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
            tcp_socket {
              port = 8443
            }
            initial_delay_seconds = 10
            period_seconds        = 10
          }

          readiness_probe {
            tcp_socket {
              port = 8443
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }
        }

        volume {
          name = "tls-certs"

          secret {
            secret_name = kubernetes_secret.hub_ca[0].metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.argocd_hub,
    kubernetes_secret.hub_ca
  ]
}

# =============================================================================
# AGENT PRINCIPAL SERVICE
# =============================================================================

resource "kubernetes_service" "agent_principal" {
  count    = 0 # Disabled - kustomize creates this
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-principal"
    namespace = var.hub_namespace

    labels = {
      "app.kubernetes.io/name"      = "argocd-agent-principal"
      "app.kubernetes.io/component" = "agent-principal"
    }
  }

  spec {
    type = "ClusterIP"

    port {
      name        = "grpc"
      port        = 8443
      target_port = 8443
      protocol    = "TCP"
    }

    port {
      name        = "metrics"
      port        = 8080
      target_port = 8080
      protocol    = "TCP"
    }

    selector = {
      "app.kubernetes.io/name" = "argocd-agent-principal"
    }
  }
}

# =============================================================================
# TLS PASSTHROUGH INGRESS FOR AGENT PRINCIPAL
# =============================================================================

resource "kubernetes_ingress_v1" "agent_principal" {
  count    = var.deploy_hub && var.hub_principal_host != "" ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-principal"
    namespace = var.hub_namespace

    annotations = {
      "nginx.ingress.kubernetes.io/ssl-passthrough"  = "true"
      "nginx.ingress.kubernetes.io/backend-protocol" = "GRPC"
      "cert-manager.io/cluster-issuer"               = var.cert_issuer_kind == "ClusterIssuer" ? var.cert_issuer_name : null
      "cert-manager.io/issuer"                       = var.cert_issuer_kind == "Issuer" ? var.cert_issuer_name : null
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [var.hub_principal_host]
      secret_name = "argocd-agent-principal-tls"
    }

    rule {
      host = var.hub_principal_host

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-agent-principal" # Service created by kustomize
              port {
                number = 8443
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.agent_principal_install,
    module.hub_cert_manager,
    module.hub_ingress_nginx
  ]
}

# =============================================================================
# REDIS NETWORK POLICY (CRITICAL)
# Must include agent-principal in allowed pods
# =============================================================================

resource "kubernetes_network_policy" "redis_allow_principal" {
  count    = var.deploy_hub ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name      = "redis-allow-principal"
    namespace = var.hub_namespace
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "redis"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "argocd-agent-principal"
          }
        }
      }

      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "argocd-server"
          }
        }
      }

      from {
        pod_selector {
          match_labels = {
            "app.kubernetes.io/name" = "argocd-applicationset-controller"
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd_hub]
}
