# Adopting Existing Ingress Controller Installation

This guide walks you through adopting an existing NGINX Ingress Controller installation into Terraform management.

## Prerequisites

- Existing NGINX Ingress Controller
- Terraform >= 1.0
- `kubectl` and `helm` CLI installed

---

## Step 1: Discover Existing Installation

Run these commands to gather information about your current setup.

### 1. Helm Release Status

```bash
helm list -A | grep ingress

# Expected Output:
# NAME           NAMESPACE      REVISION  STATUS    CHART                 APP_VERSION
# ingress-nginx  ingress-nginx  1         deployed  ingress-nginx-4.14.1  1.14.1
```

### 2. Ingress Class

Check the name of your Ingress Class.

```bash
kubectl get ingressclass

# Expected Output:
# NAME   CONTROLLER             PARAMETERS   AGE
# nginx  k8s.io/ingress-nginx   <none>       30d
```

### 3. LoadBalancer Service

```bash
kubectl get svc -n ingress-nginx ingress-nginx-controller
```

**Record these values**:
- Release Name (e.g., `ingress-nginx`)
- Namespace (e.g., `ingress-nginx`)
- Chart Version (e.g., `4.14.1`)
- IngressClass Name (e.g., `nginx`)

---

## Step 2: Configure `terraform.tfvars`

Navigate to the Terraform directory:

```bash
cd ingress-controller/terraform
```

> [!IMPORTANT]
> **Critical**: You MUST set `install_nginx_ingress = true` to create the Terraform resource configuration before importing.

Copy the template:

```bash
cp terraform.tfvars.template terraform.tfvars
```

Update `terraform.tfvars`:

```hcl
# Enable the module
install_nginx_ingress = true

# Match your existing installation
nginx_ingress_version      = "4.14.1"         # Update to match helm list
nginx_ingress_namespace    = "ingress-nginx"
nginx_ingress_release_name = "ingress-nginx"
ingress_class_name         = "nginx"
```

---

## Step 3: Initialize Terraform

```bash
terraform init
```

---

## Step 4: Import Resources

You must import the Helm Release.

### 1. Import Helm Release

Format: `<namespace>/<release_name>`

```bash
terraform import 'helm_release.nginx_ingress[0]' ingress-nginx/ingress-nginx
```

---

## Step 5: Verify the Import

```bash
terraform plan
```

**Expected output**: Should show **no changes** or only minor metadata updates.

> [!WARNING]
> If you see changes to `spec.controller` for the IngressClass, **DO NOT APPLY**. This field is immutable. Ensure your `ingress_class_name` matches the existing one.

---

## Common Issues

### Error: "IngressClass field is immutable"
**Cause**: Terraform is trying to change the `controller` field (e.g., from `k8s.io/nginx` to `k8s.io/ingress-nginx`).
**Fix**: Update `ingress_class_name` or manually delete the IngressClass to let Terraform recreate it.

---

## Next Steps

1. **Verify Routing**: Ensure existing Ingresses still work.
2. **Backup**: Commit your `terraform.tfstate`.
