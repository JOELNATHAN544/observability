# Cert-Manager Deployment (Terraform)

This guide explains how to deploy **Cert-Manager** using the standalone Terraform configuration.

## Prerequisites

- **Terraform** >= 1.0
- **Kubernetes Cluster** (GKE, etc.)
- **kubectl** configured to context

## Deployment Steps

Make sure you've cloned the repository before running Terraform.

```bash
git clone https://github.com/Adorsys-gis/observability.git
cd observability
```

1. **Verify Context** :
   Ensure you are pointing to the correct cluster before running Terraform.
   ```bash
   kubectl config current-context
   ```

2. **Navigate to the directory**:
   From the project root:
   ```bash
   cd cert-manager/terraform
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
   Open `terraform.tfvars` and update the values to match your requirements (or existing installation).

   ```hcl
   install_cert_manager = true
   letsencrypt_email    = "admin@example.com"
   # release_name       = "cert-manager"
   ```

5. **Review the Plan**:
   ```bash
   terraform plan
   ```

6. **Apply**:
   ```bash
   terraform apply
   ```

## Variables

For detailed variable descriptions, see [variables.tf](../cert-manager/terraform/variables.tf).

| Variable | Description | Default |
|----------|-------------|---------|  
| `install_cert_manager` | Enable Cert-Manager installation | `false` |
| `release_name` | Helm release name | `cert-manager` |
| `namespace` | Kubernetes namespace | `cert-manager` |
| `cert_manager_version` | Helm chart version | `v1.16.2` |
| `letsencrypt_email` | Email for Let's Encrypt notifications | **Required** |
| `cert_issuer_kind` | Issuer type: `ClusterIssuer` or `Issuer` | `ClusterIssuer` |
| `cert_issuer_name` | Name of the issuer | `letsencrypt-prod` |
| `issuer_namespace` | Namespace for Issuer (only if `cert_issuer_kind = "Issuer"`) | `cert-manager` |
