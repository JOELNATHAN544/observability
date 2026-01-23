# ⚠️ IMPORTANT: Do Not Use This Directory Directly

This root `terraform/` directory is **NOT** used for deployments.

## Correct Usage

All Terraform operations should be performed from the **environment-specific** directory:

```bash
cd environments/prod/
terraform init
terraform plan
terraform apply
```

## Why This Structure?

The modular environment structure provides:

- ✅ **Separation of Concerns**: Hub and spoke modules are reusable
- ✅ **Environment Isolation**: Dev, staging, prod can coexist
- ✅ **Better State Management**: Each environment has its own state
- ✅ **Cleaner Workspaces**: No root-level state files or lock files

## Directory Contents

This root directory contains:

- **`environments/`** - Environment configurations (USE THIS)
  - `prod/` - Production environment (start here)
- **`modules/`** - Reusable Terraform modules
  - `hub-cluster/` - Hub cluster resources
  - `spoke-cluster/` - Spoke cluster resources
- **Documentation Files**:
  - `README.md` - Main documentation
  - `TIMEOUTS.md` - Timeout configuration guide
  - `RBAC.md` - RBAC and SSO configuration guide
  - `.tflint.hcl` - TFLint configuration

## Quick Start

```bash
# 1. Navigate to production environment
cd environments/prod/

# 2. Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# 3. Edit with your values
nano terraform.tfvars

# 4. Initialize Terraform
terraform init

# 5. Deploy
terraform plan
terraform apply
```

## Documentation

- **[README.md](./README.md)** - Architecture and deployment overview
- **[TIMEOUTS.md](./TIMEOUTS.md)** - Timeout configuration and tuning
- **[RBAC.md](./RBAC.md)** - RBAC and Keycloak SSO setup
- **[Deployment Guide](../../docs/argocd-agent-terraform-deployment.md)** - Step-by-step instructions
- **[Troubleshooting](../../docs/argocd-agent-troubleshooting.md)** - Common issues and solutions

## Migration from Root Directory

If you previously used this root directory for deployments:

1. **Backup your state**:
   ```bash
   terraform state pull > terraform.tfstate.backup
   ```

2. **Move to environments/prod/**:
   ```bash
   cd environments/prod/
   ```

3. **Import existing resources** (if needed):
   ```bash
   terraform import module.hub_cluster[0].kubernetes_namespace.hub_argocd argocd
   # ... import other resources as needed
   ```

4. **Verify with refresh**:
   ```bash
   terraform plan -refresh-only
   ```

## Still Need Help?

See the main [README.md](./README.md) for comprehensive documentation.
