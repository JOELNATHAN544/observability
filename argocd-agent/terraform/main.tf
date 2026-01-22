# =============================================================================
# ArgoCD Agent Terraform Configuration
# Hub-and-Spoke Architecture for Multi-Cluster GitOps
# Translated from verified shell scripts: 01-05-*.sh
# =============================================================================

# =============================================================================
# SECTION 1: INFRASTRUCTURE MODULES (Conditional)
# =============================================================================

module "cert_manager" {
  count  = var.deploy_hub && var.install_cert_manager ? 1 : 0
  source = "../../cert-manager/terraform"

  providers = {
    kubernetes = kubernetes.hub
    helm       = helm
  }

  install_cert_manager = true
  cert_manager_version = var.cert_manager_version
  release_name         = var.cert_manager_release_name
  namespace            = var.cert_manager_namespace
  letsencrypt_email    = var.letsencrypt_email
  cert_issuer_name     = var.cert_issuer_name
  cert_issuer_kind     = var.cert_issuer_kind
  issuer_namespace     = var.hub_namespace
  ingress_class_name   = var.ingress_class_name
}

module "ingress_nginx" {
  count  = var.deploy_hub && var.install_nginx_ingress ? 1 : 0
  source = "../../ingress-controller/terraform"

  providers = {
    kubernetes = kubernetes.hub
    helm       = helm
  }

  install_nginx_ingress = true
  nginx_ingress_version = var.nginx_ingress_version
  release_name          = var.nginx_ingress_release_name
  namespace             = var.nginx_ingress_namespace
  ingress_class_name    = var.ingress_class_name
}

# =============================================================================
# SECTION 2: HUB CLUSTER SETUP (01-hub-setup.sh)
# NOTE: Keycloak configuration is in keycloak.tf to keep concerns separated
# =============================================================================

# 1.1 Create Namespace
resource "kubernetes_namespace" "hub_argocd" {
  count    = var.deploy_hub ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name = var.hub_namespace
  }
}

# 1.2 Install Base Argo CD (Step 1 - WITHOUT Principal)
resource "null_resource" "hub_argocd_install" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      MAX_RETRIES=3
      RETRY=0
      
      while [ $RETRY -lt $MAX_RETRIES ]; do
        echo "Installing base Argo CD on Hub (attempt $((RETRY+1))/$MAX_RETRIES)..."
        if kubectl apply -n ${var.hub_namespace} \
          --context ${var.hub_cluster_context} \
          -f https://raw.githubusercontent.com/argoproj/argo-cd/${var.argocd_version == "v0.5.3" ? "stable" : var.argocd_version}/manifests/install.yaml; then
          echo "✓ Base Argo CD installed successfully"
          break
        fi
        RETRY=$((RETRY+1))
        if [ $RETRY -lt $MAX_RETRIES ]; then
          echo "⚠ Apply failed, retrying in 10 seconds..."
          sleep 10
        else
          echo "✗ Failed after $MAX_RETRIES attempts"
          exit 1
        fi
      done
      
      echo "Waiting for argocd-server deployment to be available..."
      kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context}
      
      echo "Waiting for argocd-repo-server deployment to be available..."
      kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-repo-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context}
      
      echo "✓ All core Argo CD components are ready"
    EOT
  }

  depends_on = [
    kubernetes_namespace.hub_argocd
  ]

  triggers = {
    version = var.argocd_version
  }
}

# 1.3 Enable Apps-in-Any-Namespace and Configure Timeouts
resource "null_resource" "hub_apps_any_namespace" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch configmap argocd-cmd-params-cm -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch '{"data":{
          "application.namespaces":"*",
          "controller.repo.server.timeout.seconds":"300",
          "server.connection.status.cache.expiration":"1h"
        }}'
      
      kubectl rollout restart deployment argocd-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context}
      
      kubectl rollout status deployment/argocd-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} --timeout=300s
      
      echo "✓ Apps-in-any-namespace enabled and timeouts configured"
    EOT
  }

  depends_on = [null_resource.hub_argocd_install]
}

# 1.3b Configure ArgoCD Reconciliation Timeouts for Agent Architecture
# Required for resource-proxy to complete API discovery through agent connections
resource "null_resource" "hub_argocd_timeouts" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch configmap argocd-cm -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch '{"data":{
          "timeout.reconciliation":"600s",
          "timeout.hard.reconciliation":"0"
        }}'
      
      kubectl rollout restart deployment argocd-application-controller -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context}
      
      kubectl rollout status statefulset/argocd-application-controller -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} --timeout=300s
      
      echo "✓ ArgoCD reconciliation timeouts configured for agent architecture"
    EOT
  }

  depends_on = [null_resource.hub_apps_any_namespace]
}

# 1.4 Expose ArgoCD UI via Ingress
resource "kubernetes_ingress_v1" "argocd_ui" {
  count    = var.deploy_hub && var.ui_expose_method == "ingress" ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name      = "argocd-server"
    namespace = var.hub_namespace
    annotations = {
      "cert-manager.io/${var.cert_issuer_kind == "ClusterIssuer" ? "cluster-issuer" : "issuer"}" = var.cert_issuer_name
      "nginx.ingress.kubernetes.io/ssl-passthrough"                                              = "true"
      "nginx.ingress.kubernetes.io/backend-protocol"                                             = "HTTPS"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [var.argocd_host]
      secret_name = "argocd-server-tls"
    }

    rule {
      host = var.argocd_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-server"
              port {
                number = 443
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.hub_argocd_install,
    module.cert_manager,
    module.ingress_nginx
  ]
}

# 1.4 Expose ArgoCD UI via LoadBalancer
resource "null_resource" "argocd_ui_loadbalancer" {
  count = var.deploy_hub && var.ui_expose_method == "loadbalancer" ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch svc argocd-server -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --patch '{"spec":{"type":"LoadBalancer"}}'
    EOT
  }

  depends_on = [null_resource.hub_argocd_install]
}

# =============================================================================
# SECTION 4: PKI & PRINCIPAL SETUP (02-hub-pki-principal.sh)
# CRITICAL ORDERING (per official docs):
# 1. ArgoCD Control Plane installed and ready (done in Section 3)
# 2. PKI init
# 3. Principal install
# 4. Issue certs
# =============================================================================

# 2.1 Initialize PKI (after ArgoCD apps-in-any-namespace is configured)
resource "null_resource" "pki_init" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      ${var.argocd_agentctl_path} pki init \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace}
    EOT
  }

  depends_on = [null_resource.hub_apps_any_namespace]

  triggers = {
    context   = var.hub_cluster_context
    namespace = var.hub_namespace
  }
}

# 2.1.1 Issue Principal Server Certificate (BEFORE deployment so pod can start)
resource "null_resource" "principal_server_cert_early" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      ${var.argocd_agentctl_path} pki issue principal \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --ip "127.0.0.1" \
        --dns "localhost,argocd-agent-principal.${var.hub_namespace}.svc.cluster.local,argocd-agent-principal.${var.hub_namespace}.svc" \
        --upsert
    EOT
  }

  depends_on = [null_resource.pki_init]
}

# 3.1 Deploy Principal (AFTER PKI init and cert issued, AFTER ArgoCD components ready - Step 3)
resource "null_resource" "principal_install" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      MAX_RETRIES=3
      RETRY=0
      
      while [ $RETRY -lt $MAX_RETRIES ]; do
        echo "Installing Principal ref=${var.argocd_version} (attempt $((RETRY+1))/$MAX_RETRIES)..."
        if kubectl apply -n ${var.hub_namespace} \
          --context ${var.hub_cluster_context} \
          -k "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/principal?ref=${var.argocd_version}"; then
          echo "✓ Principal manifests applied successfully"
          break
        fi
        RETRY=$((RETRY+1))
        if [ $RETRY -lt $MAX_RETRIES ]; then
          echo "⚠ Apply failed, retrying in 10 seconds..."
          sleep 10
        else
          echo "✗ Failed after $MAX_RETRIES attempts"
          exit 1
        fi
      done
      
      # Wait for Principal pods to be ready
      echo "Waiting for Principal deployment to be ready..."
      kubectl rollout status deployment/argocd-agent-principal \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --timeout=300s
      
      echo "✓ Principal is ready"
    EOT
  }

  depends_on = [null_resource.principal_server_cert_early]

  triggers = {
    version = var.argocd_version
  }
}

# Patch Redis NetworkPolicy (allow Principal access)
resource "null_resource" "redis_netpol_patch" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch netpol argocd-redis-network-policy -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='json' \
        -p='[{"op": "add", "path": "/spec/ingress/0/from/-", "value": {"podSelector": {"matchLabels": {"app.kubernetes.io/name": "argocd-agent-principal"}}}}]' \
        2>/dev/null || echo "NetPol already patched or doesn't exist"
    EOT
  }

  depends_on = [null_resource.principal_install]
}

# 3.2 Expose Principal Service (Conditional based on method)
resource "null_resource" "principal_loadbalancer" {
  count = var.deploy_hub && var.principal_expose_method == "loadbalancer" ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch svc argocd-agent-principal -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --patch '{"spec":{"type":"LoadBalancer"}}'
    EOT
  }

  depends_on = [null_resource.principal_install]
}

# 3.2b Expose Principal via NodePort (Fallback for local clusters)
resource "null_resource" "principal_nodeport" {
  count = var.deploy_hub && var.principal_expose_method == "nodeport" ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch svc argocd-agent-principal -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --patch '{"spec":{"type":"NodePort"}}'
    EOT
  }

  depends_on = [null_resource.principal_install]
}

# Wait for Principal Address (IP or Hostname)
data "external" "principal_address" {
  count = var.deploy_hub ? 1 : 0

  program = ["bash", "-c", <<-EOT
    # 1. Handle Ingress
    if [ "${var.principal_expose_method}" = "ingress" ]; then
      if [ -n "${var.principal_ingress_host}" ]; then
        echo "{\"address\": \"${var.principal_ingress_host}\", \"port\": \"443\"}"
        exit 0
      fi
    fi

    # 2. Handle NodePort
    if [ "${var.principal_expose_method}" = "nodeport" ]; then
      # Get node IP and node port
      NODE_IP=$(kubectl get nodes --context ${var.hub_cluster_context} -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
      NODE_PORT=$(kubectl get svc argocd-agent-principal -n ${var.hub_namespace} --context ${var.hub_cluster_context} -o jsonpath='{.spec.ports[?(@.name=="grpc")].nodePort}' 2>/dev/null || \
                 kubectl get svc argocd-agent-principal -n ${var.hub_namespace} --context ${var.hub_cluster_context} -o jsonpath='{.spec.ports[0].nodePort}')
      
      if [ -n "$NODE_IP" ] && [ -n "$NODE_PORT" ]; then
        echo "{\"address\": \"$NODE_IP\", \"port\": \"$NODE_PORT\"}"
        exit 0
      fi
    fi

    # 3. Handle LoadBalancer (Default fallback)
    # First, check if the service exists to avoid long wait if it was deleted
    if ! kubectl get svc argocd-agent-principal -n ${var.hub_namespace} --context ${var.hub_cluster_context} >/dev/null 2>&1; then
      echo "{\"address\": \"pending\", \"port\": \"443\"}"
      exit 0
    fi

    PRINCIPAL_IP=""
    RETRY_COUNT=0
    MAX_RETRIES=60 # 5 minutes
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
      PRINCIPAL_IP=$(kubectl get svc argocd-agent-principal -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
      
      if [ -z "$PRINCIPAL_IP" ]; then
        PRINCIPAL_IP=$(kubectl get svc argocd-agent-principal -n ${var.hub_namespace} \
          --context ${var.hub_cluster_context} \
          -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
      fi
      
      if [ -n "$PRINCIPAL_IP" ]; then
        echo "{\"address\": \"$PRINCIPAL_IP\", \"port\": \"443\"}"
        exit 0
      fi
      
      RETRY_COUNT=$((RETRY_COUNT + 5))
      sleep 5
    done
    
    # If all fails, return pending
    echo "{\"address\": \"pending\", \"port\": \"443\"}"
    exit 1
  EOT
  ]

  depends_on = [
    null_resource.principal_loadbalancer,
    null_resource.principal_nodeport,
    kubernetes_ingress_v1.principal_grpc
  ]
}

# 3.2b Expose Principal via Ingress (Optional, in addition to LoadBalancer)
resource "kubernetes_ingress_v1" "principal_grpc" {
  count    = var.deploy_hub && var.enable_principal_ingress && var.principal_ingress_host != "" ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-principal"
    namespace = var.hub_namespace
    annotations = {
      "cert-manager.io/${var.cert_issuer_kind == "ClusterIssuer" ? "cluster-issuer" : "issuer"}" = var.cert_issuer_name
      "nginx.ingress.kubernetes.io/ssl-passthrough"                                              = "true"
      "nginx.ingress.kubernetes.io/backend-protocol"                                             = "HTTPS"
      "nginx.ingress.kubernetes.io/service-upstream"                                             = "true"
    }
  }

  spec {
    ingress_class_name = var.ingress_class_name

    tls {
      hosts       = [var.principal_ingress_host]
      secret_name = "principal-server-tls"
    }

    rule {
      host = var.principal_ingress_host
      http {
        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = "argocd-agent-principal"
              port {
                number = 443
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    null_resource.principal_install,
    module.cert_manager,
    module.ingress_nginx
  ]
}

# 2.2 Update Principal Certificate with LoadBalancer IP (after LB IP is assigned)
resource "null_resource" "principal_server_cert" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      PRINCIPAL_IP="${data.external.principal_address[0].result.address}"
      
      if [ "$PRINCIPAL_IP" = "pending" ] || [ "$PRINCIPAL_IP" = "error" ]; then
        echo "ERROR: Cannot update certificate - LoadBalancer not ready"
        exit 1
      fi
      
      echo "Updating Principal certificate with LoadBalancer IP: $PRINCIPAL_IP"
      ${var.argocd_agentctl_path} pki issue principal \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --ip "127.0.0.1,$PRINCIPAL_IP" \
        --dns "localhost,argocd-agent-principal.${var.hub_namespace}.svc.cluster.local,argocd-agent-principal.${var.hub_namespace}.svc" \
        --upsert
      
      # Restart Principal pod to pick up new certificate
      kubectl rollout restart deployment/argocd-agent-principal \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context}
      
      # Wait for new pod to be ready
      kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=argocd-agent-principal \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --timeout=300s
    EOT
  }

  depends_on = [data.external.principal_address]
}

# 2.2 Issue Resource Proxy Certificate (Argo CD connects to this)
resource "null_resource" "resource_proxy_cert" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      ${var.argocd_agentctl_path} pki issue resource-proxy \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --ip "127.0.0.1" \
        --dns "localhost,argocd-agent-resource-proxy.${var.hub_namespace}.svc.cluster.local" \
        --upsert
    EOT
  }

  depends_on = [null_resource.pki_init]
}

# 2.3 Create JWT Signing Key
resource "null_resource" "jwt_key" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      ${var.argocd_agentctl_path} jwt create-key \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --upsert
    EOT
  }

  depends_on = [null_resource.pki_init]
}

# Configure Principal (allowed-namespaces)
locals {
  all_agent_names    = keys(var.workload_clusters)
  allowed_namespaces = length(local.all_agent_names) > 0 ? join(",", local.all_agent_names) : "default"
}

resource "null_resource" "principal_allowed_namespaces" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch configmap argocd-agent-params -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='merge' \
        --patch '{
          "data": {
            "principal.allowed-namespaces": "'"${local.allowed_namespaces}"'"
          }
        }'
    EOT
  }

  depends_on = [null_resource.principal_install]

  triggers = {
    namespaces = local.allowed_namespaces
  }
}

# Restart Principal to apply all changes
resource "null_resource" "principal_restart" {
  count = var.deploy_hub ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl rollout restart deployment argocd-agent-principal -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context}
      
      kubectl rollout status deployment/argocd-agent-principal -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} --timeout=300s
    EOT
  }

  depends_on = [
    null_resource.principal_server_cert,
    null_resource.resource_proxy_cert,
    null_resource.jwt_key,
    null_resource.principal_allowed_namespaces,
    null_resource.redis_netpol_patch
  ]
}

# =============================================================================
# SECTION 5: WORKLOAD CLUSTERS SETUP (03-spoke-setup.sh)
# =============================================================================

# 4.2 Create Namespace
resource "null_resource" "spoke_namespace" {
  for_each = var.deploy_spokes ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      if ! kubectl get namespace ${var.spoke_namespace} --context ${each.value} >/dev/null 2>&1; then
        kubectl create namespace ${var.spoke_namespace} --context ${each.value}
      else
        echo "Namespace ${var.spoke_namespace} already exists in ${each.value}"
      fi
    EOT
  }

  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Deleting namespace ${var.spoke_namespace} from ${each.value}..."
      
      # Delete namespace (this will cascade delete all resources)
      kubectl delete namespace ${var.spoke_namespace} --context ${each.value} --ignore-not-found=true --timeout=120s || {
        echo "Force deleting stuck namespace..."
        kubectl patch namespace ${var.spoke_namespace} -p '{"metadata":{"finalizers":null}}' --context ${each.value} 2>/dev/null || true
        kubectl delete namespace ${var.spoke_namespace} --context ${each.value} --ignore-not-found=true --grace-period=0 --force || true
      }
      
      echo "✓ Namespace ${var.spoke_namespace} deleted from ${each.value}"
    EOT
  }

  triggers = {
    context = each.value
  }
}

# 4.3 Install Argo CD (Agent-Managed Profile)
resource "null_resource" "spoke_argocd_install" {
  for_each = var.deploy_spokes ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    environment = {
      GIT_HTTP_USER_AGENT = "kubectl-kustomize"
    }
    command = <<-EOT
      set -e
      MAX_RETRIES=5
      RETRY=0
      
      while [ $RETRY -lt $MAX_RETRIES ]; do
        echo "Installing Argo CD (Agent-Managed) ref=${var.argocd_version} for ${each.key} (attempt $((RETRY+1))/$MAX_RETRIES)..."
        if timeout 180 kubectl apply -n ${var.spoke_namespace} \
          --context ${each.value} \
          --server-side=true \
          --timeout=120s \
          -k "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/argo-cd/agent-managed?ref=${var.argocd_version}"; then
          echo "✓ ArgoCD manifests applied successfully to ${each.key}"
          break
        fi
        RETRY=$((RETRY+1))
        if [ $RETRY -lt $MAX_RETRIES ]; then
          echo "⚠ Apply failed (git timeout or network issue), retrying in 15 seconds..."
          sleep 15
        else
          echo "✗ Failed after $MAX_RETRIES attempts"
          exit 1
        fi
      done
      
      echo "Waiting for argocd-repo-server to be ready..."
      kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-repo-server -n ${var.spoke_namespace} \
        --context ${each.value}
      
      echo "✓ Argo CD Agent-Managed components are ready on ${each.key}"
    EOT
  }

  depends_on = [
    null_resource.spoke_namespace
  ]

  triggers = {
    version = var.argocd_version
  }
}

# Patch argocd-secret with server.secretkey (Critical for Agent-Managed mode)
resource "null_resource" "spoke_secret_patch" {
  for_each = var.deploy_spokes ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      SECRET_KEY=$(openssl rand -base64 32 | base64 -w 0 2>/dev/null || openssl rand -base64 32 | base64)
      kubectl patch secret argocd-secret -n ${var.spoke_namespace} \
        --context ${each.value} \
        --patch "{\"data\":{\"server.secretkey\":\"$SECRET_KEY\"}}" \
        || echo "Secret patch warning (ignore if first run)"
    EOT
  }

  depends_on = [null_resource.spoke_argocd_install]
}

# k3s Redis Workaround (HostNetwork + delete NetworkPolicy)
resource "null_resource" "spoke_k3s_redis_fix" {
  for_each = var.deploy_spokes ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      if kubectl get node -o wide --context ${each.value} 2>/dev/null | grep -q "k3s"; then
        echo "Detected k3s cluster on ${each.key}. Applying Redis HostNetwork workaround..."
        
        kubectl patch deployment argocd-redis -n ${var.spoke_namespace} \
          --context ${each.value} \
          --patch '{"spec": {"template": {"spec": {"hostNetwork": true, "dnsPolicy": "ClusterFirstWithHostNet"}}}}'
        
        kubectl delete networkpolicy argocd-redis-network-policy -n ${var.spoke_namespace} \
          --context ${each.value} --ignore-not-found=true
        
        kubectl rollout status deployment/argocd-redis -n ${var.spoke_namespace} \
          --context ${each.value} --timeout=120s
      else
        echo "Cluster ${each.key} is not k3s. Skipping Redis workaround."
      fi
    EOT
  }

  depends_on = [null_resource.spoke_argocd_install]
}

# Wait for ArgoCD Components
resource "null_resource" "spoke_wait_ready" {
  for_each = var.deploy_spokes ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl rollout status statefulset/argocd-application-controller -n ${var.spoke_namespace} \
        --context ${each.value} --timeout=300s
      
      kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-repo-server -n ${var.spoke_namespace} \
        --context ${each.value}
    EOT
  }

  depends_on = [
    null_resource.spoke_secret_patch,
    null_resource.spoke_k3s_redis_fix
  ]
}

# =============================================================================
# SECTION 6: AGENT CONNECTION TO HUB (04-agent-connect.sh)
# CRITICAL: Exact script order
# =============================================================================

# Generate random passwords for agent resource proxy authentication
resource "random_password" "agent_proxy_password" {
  for_each         = var.workload_clusters
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
  min_upper        = 2
  min_lower        = 2
  min_numeric      = 2
  min_special      = 2
}

# 5.1 Create Agent Configuration on Hub (Step 5.1)
resource "null_resource" "agent_create" {
  for_each = var.deploy_spokes ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Delete existing for idempotency
      kubectl delete secret cluster-${each.key} -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} --ignore-not-found=true
      
      ${var.argocd_agentctl_path} agent create ${each.key} \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --resource-proxy-server argocd-agent-resource-proxy.${var.hub_namespace}.svc.cluster.local:9090
    EOT
  }

  depends_on = [
    null_resource.principal_restart,
    null_resource.spoke_wait_ready
  ]

  triggers = {
    agent = each.key
  }
}

# 5.5 Create Agent Namespace on Hub (for Managed Mode - Step 5.5)
resource "kubernetes_namespace" "agent_managed_namespace" {
  for_each = var.deploy_hub && var.deploy_spokes ? var.workload_clusters : {}
  provider = kubernetes.hub

  metadata {
    name = each.key
  }

  depends_on = [null_resource.agent_create]
}

# Update Principal allowed-namespaces (incremental update in script)
# Note: Terraform manages this differently - we set all namespaces upfront
# in principal_allowed_namespaces resource, then restart once

# 5.2 Issue Agent Client Certificate
resource "null_resource" "agent_client_cert" {
  for_each = var.deploy_spokes ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Delete existing for idempotency
      kubectl delete secret argocd-agent-client-tls -n ${var.spoke_namespace} \
        --context ${each.value} --ignore-not-found=true
      
      ${var.argocd_agentctl_path} pki issue agent ${each.key} \
        --principal-context ${var.hub_cluster_context} \
        --agent-context ${each.value} \
        --agent-namespace ${var.spoke_namespace} \
        --upsert
    EOT
  }

  depends_on = [null_resource.agent_create]
}

# 5.3 Propagate CA to Spoke
resource "null_resource" "agent_pki_propagate" {
  for_each = var.deploy_spokes ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Delete existing for idempotency
      kubectl delete secret argocd-agent-ca -n ${var.spoke_namespace} \
        --context ${each.value} --ignore-not-found=true
      
      ${var.argocd_agentctl_path} pki propagate \
        --principal-context ${var.hub_cluster_context} \
        --principal-namespace ${var.hub_namespace} \
        --agent-context ${each.value} \
        --agent-namespace ${var.spoke_namespace}
    EOT
  }

  depends_on = [null_resource.agent_client_cert]
}

# 5.4 Verify Certificates (implicit in Terraform - will fail if missing)

# 5.6 Deploy Agent (PHASE 1: Apply manifests without waiting)
resource "null_resource" "agent_install" {
  for_each = var.deploy_spokes ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -e
      MAX_RETRIES=3
      RETRY=0
      
      while [ $RETRY -lt $MAX_RETRIES ]; do
        echo "Installing Agent ref=${var.argocd_version} for ${each.key} (attempt $((RETRY+1))/$MAX_RETRIES)..."
        if kubectl apply -n ${var.spoke_namespace} \
          --context ${each.value} \
          --server-side=true \
          --force-conflicts=true \
          -k "https://github.com/argoproj-labs/argocd-agent/install/kubernetes/agent?ref=${var.argocd_version}"; then
          echo "✓ Agent manifests applied successfully to ${each.key}"
          break
        fi
        RETRY=$((RETRY+1))
        if [ $RETRY -lt $MAX_RETRIES ]; then
          echo "⚠ Apply failed, retrying in 10 seconds..."
          sleep 10
        else
          echo "✗ Failed after $MAX_RETRIES attempts"
          exit 1
        fi
      done
      
      echo "✓ Agent manifests deployed to ${each.key} (configuration will be applied next)"
    EOT
  }

  depends_on = [
    null_resource.agent_pki_propagate,
    kubernetes_namespace.agent_managed_namespace
  ]

  triggers = {
    version = var.argocd_version
  }
}

# 5.7 Configure Agent Connection (PHASE 2: Patch ConfigMap with mTLS configuration)
# CRITICAL: This must run BEFORE the agent pod starts, otherwise it will crash
# with "could not load creds: open /app/config/creds/userpass.creds: no such file"
resource "null_resource" "agent_configure" {
  for_each = var.deploy_spokes ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      PRINCIPAL_ADDR="${var.deploy_hub ? data.external.principal_address[0].result.address : var.principal_address}"
      PRINCIPAL_PORT="${var.deploy_hub ? data.external.principal_address[0].result.port : var.principal_port}"
      
      if [ "$PRINCIPAL_ADDR" = "pending" ]; then
        echo "ERROR: Principal address not available"
        exit 1
      fi
      
      echo "Configuring agent ${each.key} to connect to Principal at $PRINCIPAL_ADDR:$PRINCIPAL_PORT"
      
      # Configure agent in managed mode with mTLS authentication
      kubectl patch configmap argocd-agent-params -n ${var.spoke_namespace} \
        --context ${each.value} \
        --type='merge' \
        --patch "{\"data\":{
          \"agent.server.address\":\"$PRINCIPAL_ADDR\",
          \"agent.server.port\":\"$PRINCIPAL_PORT\",
          \"agent.mode\":\"managed\",
          \"agent.creds\":\"mtls:^CN=(.+)$\",
          \"agent.tls.client.insecure\":\"false\",
          \"agent.tls.secret-name\":\"argocd-agent-client-tls\",
          \"agent.tls.root-ca-secret-name\":\"argocd-agent-ca\",
          \"agent.log.level\":\"info\"
        }}"
      
      echo "✓ Agent ${each.key} configured with mTLS authentication"
    EOT
  }

  depends_on = [null_resource.agent_install]
}

# PHASE 3: Restart Agent and Wait for Ready
# Now that configuration is applied, restart the deployment and wait for it to be ready
resource "null_resource" "agent_restart" {
  for_each = var.deploy_spokes ? var.workload_clusters : {}

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      echo "Restarting agent ${each.key} to apply mTLS configuration..."
      
      # Force rollout to pick up new ConfigMap
      kubectl rollout restart deployment/argocd-agent-agent \
        -n ${var.spoke_namespace} --context ${each.value}
      
      # Wait for rollout to complete
      kubectl rollout status deployment/argocd-agent-agent \
        -n ${var.spoke_namespace} --context ${each.value} --timeout=300s
      
      echo "✓ Agent ${each.key} is ready and connected"
      
      # Verify agent is actually running
      READY_PODS=$(kubectl get pods -n ${var.spoke_namespace} \
        --context ${each.value} \
        -l app.kubernetes.io/name=argocd-agent-agent \
        -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}')
      
      if [[ "$READY_PODS" == *"True"* ]]; then
        echo "✓ Agent pod is healthy"
      else
        echo "⚠ WARNING: Agent pod may not be healthy. Check logs with:"
        echo "  kubectl logs -l app.kubernetes.io/name=argocd-agent-agent -n ${var.spoke_namespace} --context ${each.value}"
      fi
    EOT
  }

  depends_on = [null_resource.agent_configure]
}
