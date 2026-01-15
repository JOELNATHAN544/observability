# =============================================================================
# SUPPLEMENTAL RBAC FOR AGENT PRINCIPAL
# Fixes missing permissions in official manifests
# =============================================================================

# 1. Role for Namespace-scoped resources (Secrets, AppProjects in argocd ns)
resource "kubernetes_role" "agent_principal_patch" {
  count    = var.deploy_hub ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-principal-patch"
    namespace = var.hub_namespace
  }

  # Secrets (for TLS/JWT)
  rule {
    api_groups = [""]
    resources  = ["secrets", "configmaps"]
    verbs      = ["get", "list", "watch"]
  }

  # AppProjects (often needed in the installation namespace)
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["appprojects"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_role_binding" "agent_principal_patch" {
  count    = var.deploy_hub ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name      = "argocd-agent-principal-patch"
    namespace = var.hub_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.agent_principal_patch[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-agent-principal"
    namespace = var.hub_namespace
  }
}

# 2. ClusterRole for Cluster-scoped resources (Namespaces, Applications)
resource "kubernetes_cluster_role" "agent_principal_patch" {
  count    = var.deploy_hub ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name = "argocd-agent-principal-patch"
  }

  # Namespaces (to watch for managed namespaces)
  rule {
    api_groups = [""]
    resources  = ["namespaces"]
    verbs      = ["get", "list", "watch"]
  }

  # Applications (Cluster-scoped typically for ArgoCD)
  rule {
    api_groups = ["argoproj.io"]
    resources  = ["applications", "applicationsets"]
    verbs      = ["get", "list", "watch", "update", "patch"] # update/patch might be needed
  }
}

resource "kubernetes_cluster_role_binding" "agent_principal_patch" {
  count    = var.deploy_hub ? 1 : 0
  provider = kubernetes.hub

  metadata {
    name = "argocd-agent-principal-patch"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.agent_principal_patch[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "argocd-agent-principal"
    namespace = var.hub_namespace
  }
}
