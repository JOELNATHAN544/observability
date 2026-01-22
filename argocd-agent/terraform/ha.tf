# =============================================================================
# HIGH AVAILABILITY CONFIGURATION
# =============================================================================

# Scale Principal to 2 replicas with PodDisruptionBudget
resource "null_resource" "principal_ha_replicas" {
  count = var.deploy_hub && var.principal_replicas > 1 ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      # Scale Principal deployment
      kubectl scale deployment argocd-agent-principal \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --replicas ${var.principal_replicas}
      
      # Wait for all replicas to be ready
      kubectl wait --for=condition=available --timeout=300s \
        deployment/argocd-agent-principal \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context}
      
      echo "✓ Principal scaled to ${var.principal_replicas} replicas"
    EOT
  }

  depends_on = [null_resource.principal_restart]

  triggers = {
    replicas = var.principal_replicas
  }
}

# PodDisruptionBudget to prevent all Principal pods from being down simultaneously
resource "null_resource" "principal_pdb" {
  count = var.deploy_hub && var.principal_replicas > 1 ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      cat <<PDBEOF | kubectl apply -f - --context ${var.hub_cluster_context}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: argocd-agent-principal
  namespace: ${var.hub_namespace}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: argocd-agent-principal
PDBEOF
      
      echo "✓ PodDisruptionBudget created (minAvailable: 1)"
    EOT
  }

  depends_on = [null_resource.principal_ha_replicas]

  # Note: PDB cleanup handled by cleanup.sh script
  # Terraform destroy provisioners cannot reference variables (limitation)
}

# Add pod anti-affinity for better distribution across nodes
resource "null_resource" "principal_anti_affinity" {
  count = var.deploy_hub && var.principal_replicas > 1 ? 1 : 0

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      kubectl patch deployment argocd-agent-principal \
        -n ${var.hub_namespace} \
        --context ${var.hub_cluster_context} \
        --type='strategic' \
        --patch '
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchLabels:
                  app.kubernetes.io/name: argocd-agent-principal
              topologyKey: kubernetes.io/hostname
'
      
      echo "✓ Pod anti-affinity configured (prefer different nodes)"
    EOT
  }

  depends_on = [null_resource.principal_ha_replicas]
}
