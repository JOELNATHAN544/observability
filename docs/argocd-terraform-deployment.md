# ArgoCD Deployment (Terraform)

This guide explains how to deploy **ArgoCD** with Keycloak OIDC integration using the Terraform configuration.

## Prerequisites

- **Terraform** >= 1.0
- **Kubernetes Cluster** (GKE, etc.)
- **kubectl** configured to context
- **Keycloak** instance running and accessible
- **Ingress Controller** (e.g., NGINX) installed in cluster
- **Cert-Manager** (optional but recommended for TLS)

## Deployment Steps

Make sure you've cloned the repository before running Terraform.

```bash
git clone https://github.com/Adorsys-gis/observability.git
cd observability
```

1. **Verify Context**:
   Ensure you are pointing to the correct cluster before running Terraform.
   ```bash
   kubectl config current-context
   ```

2. **Navigate to the directory**:
   From the project root:
   ```bash
   cd argocd/terraform
   ```

3. **Initialize Terraform**:
   ```bash
   terraform init
   ```

4. **Configure `terraform.tfvars`**:
   Copy the provided template:
   ```bash
   cp terraform.tfvars.template terraform.tfvars
   ```
   Open `terraform.tfvars` and update the values to match your environment:

   ```hcl
   # Keycloak OIDC
   keycloak_url      = "https://keycloak.example.com"
   keycloak_user     = "admin"
   keycloak_password = "your-secure-password"
   target_realm      = "argocd"

   # ArgoCD Settings
   argocd_url   = "https://argocd.example.com"
   kube_context = "gke_project_region_cluster"
   namespace    = "argocd"

   # Shared Infrastructure (set to false if managed elsewhere)
   install_cert_manager  = false
   install_nginx_ingress = false
   
   # If using existing infrastructure, reference it
   nginx_ingress_namespace = "ingress-nginx"
   cert_manager_namespace  = "cert-manager"
   letsencrypt_email       = "admin@example.com"
   ```

5. **Review the Plan**:
   ```bash
   terraform plan
   ```

6. **Apply**:
   ```bash
   terraform apply
   ```

7. **Retrieve Admin Password**:
   After successful deployment:
   ```bash
   terraform output -raw argocd_admin_secret
   ```

## Post-Deployment

### Access ArgoCD UI

1. Navigate to your configured ArgoCD URL (e.g., `https://argocd.example.com`)
2. Login with:
   - **Username**: `admin`
   - **Password**: Retrieved from terraform output above
3. Or login via Keycloak SSO (if configured)

### Configure Keycloak Groups (Optional)

For RBAC via Keycloak groups:

1. In Keycloak, create groups (e.g., `argocd-admins`, `argocd-developers`)
2. Assign users to groups
3. Groups will be automatically mapped to ArgoCD roles

## Variables

For detailed variable descriptions, see [variables.tf](../argocd/terraform/variables.tf).

### Keycloak Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `keycloak_url` | Keycloak server URL | **Required** |
| `keycloak_user` | Keycloak admin username | **Required** |
| `keycloak_password` | Keycloak admin password | **Required** |
| `target_realm` | Keycloak realm for ArgoCD | `argocd` |

### ArgoCD Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `argocd_url` | ArgoCD public URL | **Required** |
| `kube_context` | Kubernetes context name | `""` (uses current) |
| `namespace` | ArgoCD namespace | `cert-manager` |
| `letsencrypt_email` | Email for certificate notifications | **Required** |

### Shared Infrastructure

| Variable | Description | Default |
|----------|-------------|---------|
| `install_cert_manager` | Install Cert-Manager via Terraform | `false` |
| `install_nginx_ingress` | Install NGINX Ingress via Terraform | `false` |
| `cert_manager_version` | Cert-Manager chart version | `v1.15.0` |
| `cert_manager_release_name` | Cert-Manager release name | `cert-manager` |
| `cert_manager_namespace` | Cert-Manager namespace | `cert-manager` |
| `cert_issuer_name` | Certificate issuer name | `letsencrypt-prod` |
| `cert_issuer_kind` | Issuer type: `ClusterIssuer` or `Issuer` | `ClusterIssuer` |
| `nginx_ingress_version` | NGINX Ingress chart version | `4.10.1` |
| `nginx_ingress_release_name` | NGINX Ingress release name | `nginx-monitoring` |
| `nginx_ingress_namespace` | NGINX Ingress namespace | `ingress-nginx` |
| `ingress_class_name` | IngressClass name | `nginx` |

## See Also

- [Manual ArgoCD Deployment Guide](manual-argocd-deployment.md)
- [Adopting Existing ArgoCD Installation](adopting-argocd.md)
- [Troubleshooting ArgoCD](troubleshooting-argocd.md)
