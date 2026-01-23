# ArgoCD Agent Terraform Deployment

This directory contains Terraform configurations for deploying ArgoCD in a **hub-and-spoke architecture** using the ArgoCD Agent pattern for multi-cluster GitOps.

## Quick Start

**All deployments should use the modular environment configuration:**

```bash
cd environments/prod
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your configuration
terraform init
terraform plan
terraform apply
```

## Architecture

### Hub-and-Spoke Model

```
┌─────────────────────────────────────┐
│         HUB CLUSTER                 │
│  ┌──────────────────────────────┐   │
│  │ ArgoCD Control Plane         │   │
│  │ - UI Server                  │   │
│  │ - Application Controller     │   │
│  │ - Repo Server                │   │
│  └──────────────────────────────┘   │
│  ┌──────────────────────────────┐   │
│  │ Agent Principal              │   │
│  │ - gRPC Server (LoadBalancer) │   │
│  │ - PKI Certificate Authority  │   │
│  └──────────────────────────────┘   │
└─────────────────────────────────────┘
             │
    ┌────────┴────────┐
    │                 │
┌───▼────┐      ┌─────▼───┐
│ SPOKE1 │      │ SPOKE2  │
│ Agent  │      │ Agent   │
└────────┘      └─────────┘
```

## Directory Structure

```
terraform/
├── environments/
│   └── prod/              # Production environment (RECOMMENDED)
│       ├── main.tf        # Module orchestration
│       ├── variables.tf   # Variable definitions
│       ├── provider.tf    # Provider configuration
│       └── terraform.tfvars.example
├── modules/
│   ├── hub-cluster/       # Hub cluster module
│   └── spoke-cluster/     # Spoke cluster module
├── TIMEOUTS.md            # Timeout configuration guide
├── RBAC.md                # RBAC and SSO configuration guide
└── README.md              # This file
```

## Deployment Modes

### 1. Full Deployment (Hub + Spokes)

Deploy ArgoCD control plane and agents simultaneously:

```hcl
deploy_hub    = true
deploy_spokes = true
workload_clusters = {
  "prod-agent"    = "gke_project_region_prod"
  "staging-agent" = "gke_project_region_staging"
}
```

### 2. Hub Only

Deploy hub first, add spokes later:

```hcl
deploy_hub    = true
deploy_spokes = false
```

After deployment, get the Principal IP:
```bash
terraform output principal_address
```

### 3. Spokes Only (Add to Existing Hub)

Connect new spokes to an existing hub:

```hcl
deploy_hub        = false
deploy_spokes     = true
principal_address = "34.89.123.45"  # From hub output
principal_port    = 443
workload_clusters = {
  "new-agent" = "gke_project_region_new-cluster"
}
```

## Key Features

- **Multi-cluster GitOps**: Manage applications across multiple Kubernetes clusters
- **Keycloak SSO**: Optional OIDC integration with predefined RBAC groups
- **High Availability**: Configurable Principal replicas with PodDisruptionBudget
- **Flexible Exposure**: LoadBalancer or Ingress for UI and Principal
- **Resource Proxy**: Direct kubectl access to spoke clusters through hub
- **AppProject Sync**: Automatic AppProject distribution to agents

## Configuration Files

### Required Configuration

Edit `environments/prod/terraform.tfvars`:

```hcl
# Cluster contexts (from kubectl config)
hub_cluster_context = "your-hub-context"
workload_clusters = {
  "agent-1" = "spoke-context-1"
  "agent-2" = "spoke-context-2"
}

# ArgoCD version
argocd_version = "v0.5.3"

# Exposure method
ui_expose_method        = "loadbalancer"  # or "ingress"
principal_expose_method = "loadbalancer"  # or "ingress"
```

### Optional Features

**Keycloak SSO:**
```hcl
enable_keycloak   = true
keycloak_url      = "https://keycloak.example.com"
keycloak_realm    = "argocd"
argocd_url        = "https://argocd.example.com"
```

**High Availability:**
```hcl
principal_replicas = 2  # Enables HA mode with anti-affinity
```

## Documentation

- **[TIMEOUTS.md](./TIMEOUTS.md)**: Timeout configuration and tuning guide
- **[RBAC.md](./RBAC.md)**: RBAC, SSO, and Keycloak integration guide
- **[Modules](./modules/)**: Individual module documentation

## Provider Requirements

```hcl
terraform >= 1.0

providers:
  - kubernetes ~> 2.30
  - helm       ~> 2.12
  - keycloak   ~> 4.4  (optional, if enable_keycloak=true)
```

## Validation and CI

This configuration includes:
- **GitHub Actions CI**: Automatic validation on PRs
- **TFLint**: Terraform linting and best practices
- **Format checking**: Enforced code formatting

Run locally:
```bash
terraform fmt -check -recursive
terraform validate
```

## Outputs

After deployment:

```bash
# ArgoCD UI URL
terraform output argocd_url

# Principal address (for spoke additions)
terraform output principal_address

# Connected agents
terraform output deployed_agents

# PKI backup command
terraform output pki_backup_command
```

## Troubleshooting

### Common Issues

1. **LoadBalancer IP Pending**
   - Check cloud provider quotas
   - Verify network configuration
   - See `principal_loadbalancer_wait_timeout` in TIMEOUTS.md

2. **Agent Connection Failed**
   - Verify Principal address is reachable from spoke clusters
   - Check network policies and firewall rules
   - Ensure PKI certificates are valid

3. **Keycloak Integration Issues**
   - Verify Keycloak URL is accessible from hub cluster
   - Check realm and client configuration
   - See RBAC.md for detailed Keycloak setup

### Debugging

Enable detailed logging:
```bash
export TF_LOG=DEBUG
terraform apply
```

Check installation logs:
```bash
ls -lt /tmp/argocd-*.log | head
```

## Security Best Practices

1. **Never commit secrets**: Use environment variables
   ```bash
   export TF_VAR_keycloak_password="your-password"
   ```

2. **Backup PKI CA**: Critical for disaster recovery
   ```bash
   kubectl get secret argocd-agent-pki-ca -n argocd --context hub -o yaml > pki-backup.yaml
   ```

3. **Use RBAC**: Enable Keycloak SSO for production
4. **Network policies**: Restrict agent communication to Principal only
5. **Regular updates**: Keep ArgoCD version current

## Migration from Monolithic Setup

If you previously used the root directory configuration, migrate to the modular approach:

1. **Backup state**:
   ```bash
   terraform state pull > terraform.tfstate.backup
   ```

2. **Switch to prod environment**:
   ```bash
   cd environments/prod
   ```

3. **Import existing resources** (if needed):
   ```bash
   terraform import module.hub_cluster.kubernetes_namespace.hub_argocd argocd
   # ... import other resources
   ```

## Support

For issues and questions:
- Check documentation in TIMEOUTS.md and RBAC.md
- Review GitHub Actions CI results for validation errors
- Examine Terraform logs in `/tmp/argocd-*.log`

## Version Compatibility

| Component          | Version    |
|--------------------|------------|
| Terraform          | ~> 1.0     |
| ArgoCD Agent       | v0.5.3+    |
| Kubernetes         | 1.24+      |
| cert-manager       | v1.16.2+   |
| nginx-ingress      | 4.11.3+    |
| Keycloak (optional)| 20.0+      |
