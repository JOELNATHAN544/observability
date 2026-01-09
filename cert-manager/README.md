# Cert-Manager Component

This directory contains the necessary configurations for **Cert-Manager**, which handles certificate management and issuance for the observability stack.

## Deployment Options

You can deploy Cert-Manager using one of the following methods:

### 1. Terraform (Automated)
This method uses the Terraform configuration located in the `terraform/` directory. It is the recommended approach for integration with the full observability stack.

- [**Terraform Deployment Guide**](../docs/cert-manager-terraform-deployment.md)

### 2. Manual (Helm & Kubectl)
If you prefer to deploy manually using CLI tools, you can follow the manual guide.

- [**Manual Deployment Guide**](../docs/cert-manager-manual-deployment.md)
