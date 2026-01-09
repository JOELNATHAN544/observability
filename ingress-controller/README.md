# NGINX Ingress Controller Component

This directory contains the configurations for the **NGINX Ingress Controller**, which manages external access to the observability stack services.

## Deployment Options

You can deploy the Ingress Controller using one of the following methods:

### 1. Terraform (Automated)
This method uses the Terraform configuration located in the `terraform/` directory.

- [**Terraform Deployment Guide**](../docs/ingress-controller-terraform-deployment.md)

### 2. Manual (Helm)
If you prefer to deploy manually using Helm, you can follow the manual guide.

- [**Manual Deployment Guide**](../docs/ingress-controller-manual-deployment.md)
