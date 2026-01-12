# NGINX Ingress Deployment

This directory contains infrastructure-as-code and configuration for deploying the **NGINX Ingress Controller** to manage external access for services running on the cluster.

The Ingress Controller provides:
*   **Load Balancing**: Routing external traffic to internal Kubernetes services.
*   **SSL Termination**: Handling HTTPS connections (integrated with Cert-Manager).
*   **Path-based Routing**: Directing traffic to applications based on hostnames or paths.

## Deployment Options

### 1. Automated Deployment
This method uses the Terraform configuration located in the `terraform/` directory.

For detailed instructions, see the [Terraform deployment guide](../docs/ingress-controller-terraform-deployment.md).

### 2. Manual (Helm)
If you prefer to deploy manually using Helm, you can follow the [manual deployment guide](../docs/ingress-controller-manual-deployment.md).

## Adoption & Troubleshooting

### Adopting Existing Installation
If you have an existing Ingress Controller and want to manage it with Terraform, see the [Adoption Guide](../docs/adopting-ingress-controller.md).

### Troubleshooting
For common issues and their solutions, see the [Troubleshooting Guide](../docs/troubleshooting-ingress-controller.md).
