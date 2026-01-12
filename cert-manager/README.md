# Cert-Manager Deployment

This directory contains infrastructure-as-code and configuration for deploying **Cert-Manager** to automate the management and issuance of TLS certificates for the Kubernetes cluster.

Cert-Manager provides:
*   **Automated Issuance**: Obtaining certificates from Let's Encrypt and other issuers.
*   **Renewal**: Automatically renewing certificates before expiry.
*   **Integration**: Working seamlessly with Ingress resources to secure external access for any application.

## Deployment Options

### 1. Automated Deployment
This method uses the Terraform configuration located in the `terraform/` directory. It is the recommended approach for automation.

For detailed instructions, see the [Terraform deployment guide](../docs/cert-manager-terraform-deployment.md).

### 2. Manual (Helm & Kubectl)
If you prefer to deploy manually using CLI tools, you can follow the [manual deployment guide](../docs/cert-manager-manual-deployment.md).

## Adoption & Troubleshooting

### Adopting Existing Installation
If you have an existing Cert-Manager installation and want to manage it with Terraform, see the [Adoption Guide](../docs/adopting-cert-manager.md).

### Troubleshooting
For common issues and their solutions, see the [Troubleshooting Guide](../docs/troubleshooting-cert-manager.md).
