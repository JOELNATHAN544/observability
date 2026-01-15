# =============================================================================
# RBAC CONFIGURATIONS
# Hub Principal and Spoke Agent permissions
# =============================================================================

# =============================================================================
# HUB: AGENT PRINCIPAL RBAC
# =============================================================================

# Service Account for Agent Principal
resource "kubernetes_service_account" "agent_principal" {
  count    = 0 # Disabled - kustomize creates this
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-principal"
    namespace = var.hub_namespace
  }

  depends_on = [kubernetes_namespace.hub_argocd]
}

# ClusterRole for Agent Principal
# Needs access to core ArgoCD namespace and spoke management namespaces
resource "kubernetes_cluster_role" "agent_principal" {
  count = 0 # Disabled - kustomize creates this

  metadata {
    name = "argocd-agent-principal"
  }

  # Full access to ArgoCD resources
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["applications", "applicationsets", "appprojects"]
    verbs      = ["get", "list", "watch", "update", "patch"]
  }

  # Access to secrets and configmaps
  rule {
    api_groups = [""]
    resources  = ["secrets", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  # Access to namespaces (for watching spoke management namespaces)
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list", "watch"]
  }
}

# ClusterRoleBinding for Agent Principal
resource "kubernetes_cluster_role_binding" "agent_principal" {
  count = 0 # Disabled - kustomize creates this

  metadata {
    name = "argocd-agent-principal"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "argocd-agent-principal"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-agent-principal"
    namespace = var.hub_namespace
  }
}

# Role for Principal in core ArgoCD namespace (full permissions)
resource "kubernetes_role" "agent_principal_core" {
  count    = 0 # Disabled - kustomize creates RBAC
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-principal-core"
    namespace = var.hub_namespace
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding" "agent_principal_core" {
  count    = 0 # Disabled - kustomize creates RBAC
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-principal-core"
    namespace = var.hub_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "argocd-agent-principal-core"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-agent-principal"
    namespace = var.hub_namespace
  }
}

# =============================================================================
# HUB: SPOKE MANAGEMENT NAMESPACE RBAC
# Principal needs to watch Applications in spoke management namespaces
# =============================================================================

# Create spoke management namespace on Hub
resource "kubernetes_namespace" "spoke_mgmt" {
  count    = var.deploy_hub && var.deploy_spoke ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name = local.spoke_mgmt_namespace

    labels = {
      "argocd.argoproj.io/spoke-id" = var.spoke_id
      "app.kubernetes.io/component" = "spoke-management"
    }
  }
}

# Role for Principal in spoke management namespace
resource "kubernetes_role" "agent_principal_spoke_mgmt" {
  count    = var.deploy_hub && var.deploy_spoke ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-principal"
    namespace = local.spoke_mgmt_namespace
  }

  rule {
    api_groups = ["argoproj.io"]
    resources  = ["applications", "applicationsets", "appprojects"]
    verbs      = ["get", "list", "watch", "update", "patch"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  depends_on = [kubernetes_namespace.spoke_mgmt]
}

resource "kubernetes_role_binding" "agent_principal_spoke_mgmt" {
  count    = var.deploy_hub && var.deploy_spoke ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-principal"
    namespace = local.spoke_mgmt_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.agent_principal_spoke_mgmt[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.agent_principal[0].metadata[0].name
    namespace = var.hub_namespace
  }

  depends_on = [kubernetes_namespace.spoke_mgmt]
}

# =============================================================================
# SPOKE: AGENT RBAC (Pattern 1 - Single Namespace)
# =============================================================================

# Service Account for Agent
resource "kubernetes_service_account" "agent" {
  count    = var.deploy_spoke ? 1 : 0
  provider = kubernetes.spoke

  metadata {
    name      = "argocd-agent"
    namespace = var.spoke_namespace
  }

  depends_on = [kubernetes_namespace.spoke_argocd]
}

# Role for Agent in spoke ArgoCD namespace (full permissions)
resource "kubernetes_role" "agent" {
  count    = var.deploy_spoke ? 1 : 0
  provider = kubernetes.spoke

  metadata {
    name      = "argocd-agent"
    namespace = var.spoke_namespace
  }

  rule {
    api_groups = ["*"]
    resources  = ["*"]
    verbs      = ["*"]
  }
}

resource "kubernetes_role_binding" "agent" {
  count    = var.deploy_spoke ? 1 : 0
  provider = kubernetes.spoke

  metadata {
    name      = "argocd-agent"
    namespace = var.spoke_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.agent[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.agent[0].metadata[0].name
    namespace = var.spoke_namespace
  }
}


