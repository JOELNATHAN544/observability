c# NGINX Ingress Controller Deployment (Terraform)

This guide explains how to deploy the **NGINX Ingress Controller** using the standalone Terraform configuration.

## Prerequisites

- **Terraform** >= 1.0
- **Kubernetes Cluster**
- **kubectl** configured

## Deployment Steps

Make sure you've cloned the repository before running Terraform.

```bash
git clone https://github.com/Adorsys-gis/observability.git
cd observability
```

1. **Verify Context**:
   Ensure you are pointing to the correct cluster.
   ```bash
   kubectl config current-context
   ```

2. **Navigate to the directory**:
   From the project root:
   ```bash
   cd ingress-controller/terraform
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
   install_nginx_ingress = true
   # release_name          = "nginx-monitoring"
   ```

5. **Review the Plan**:
   ```bash
   terraform plan
   ```

6. **Apply**:
   ```bash
   terraform apply
   ```


## Adopting Existing Installations

If the **NGINX Ingress Controller** is already installed and you want Terraform to manage it, you must **import** it into the state.

1. **Import the Helm Release**:
   ```bash
   # Format: <namespace>/<release_name>
   terraform import helm_release.nginx_ingress ingress-nginx/nginx-monitoring
   ```
   *(Note: Adjust `nginx-monitoring` if your existing release name is different)*.

   > **Troubleshooting**: If you see `Kubernetes cluster unreachable`, try exporting the config path first:
   > ```bash
   > export KUBE_CONFIG_PATH=~/.kube/config
   > terraform import ...
   > ```

## Variables

For detailed variable descriptions, see [variables.tf](../ingress-controller/terraform/variables.tf).

| Variable | Description | Default |
|----------|-------------|---------|  
| `install_nginx_ingress` | Enable NGINX Ingress installation | `false` |
| `release_name` | Helm release name | `ingress-nginx` |
| `namespace` | Kubernetes namespace | `ingress-nginx` |
| `nginx_ingress_version` | Helm chart version | `4.14.1` |
| `replica_count` | Number of controller replicas | `1` |
| `ingress_class_name` | IngressClass name (immutable after creation) | `nginx` |
