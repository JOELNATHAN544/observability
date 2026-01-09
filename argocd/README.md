# Argo CD

Argo CD is a declarative, GitOps continuous delivery tool for Kubernetes. It automates the deployment of applications by continuously monitoring Git repositories and synchronizing the desired application state with the live state in your Kubernetes cluster.

## What is Argo CD?

Argo CD follows the **GitOps** pattern, using Git repositories as the source of truth for defining the desired application state. It provides:

- **Automated Deployment**: Automatically sync applications from Git to Kubernetes
- **Application Health Monitoring**: Continuously monitor application health and sync status
- **Rollback Capabilities**: Easy rollback to previous application versions
- **Multi-Cluster Management**: Manage deployments across multiple Kubernetes clusters
- **SSO Integration**: Support for OIDC, SAML, LDAP, and other authentication providers
- **RBAC**: Fine-grained role-based access control for multi-tenancy
- **Web UI & CLI**: Both graphical and command-line interfaces for management

## Key Features

### GitOps Workflow
- Declarative application definitions using Kubernetes manifests, Helm charts, or Kustomize
- Git as the single source of truth for application configuration
- Automated synchronization between Git repository and cluster state

### High Availability
- Support for Redis HA for session storage
- Multiple replicas for API server and repository server
- Horizontal pod autoscaling for handling increased load

### Security
- TLS/HTTPS support with automated certificate management
- Integration with cert-manager for certificate provisioning
- RBAC policies for fine-grained access control
- SSO/OIDC authentication support

### Developer Experience
- Intuitive web UI for visualizing application topology
- CLI for automation and CI/CD integration
- Real-time sync status and health monitoring
- Automated or manual sync strategies

## Architecture

Argo CD consists of several key components:

- **API Server**: Exposes the API consumed by the Web UI, CLI, and CI/CD systems
- **Repository Server**: Maintains a local cache of Git repositories holding application manifests
- **Application Controller**: Monitors running applications and compares live state against desired state
- **Redis**: Provides caching and session storage (with HA support for production)
- **ApplicationSet Controller**: Automates the generation of Argo CD applications

## Deployment Options

We provide two ways to deploy Argo CD to your Kubernetes cluster:

### 1. Manual Deployment

Deploy Argo CD manually using Helm with customizable values files. This approach gives you full control over the configuration and is ideal for:

- Learning how Argo CD works
- Custom configurations not covered by automation
- Environments where Terraform is not available

**📖 [Manual Deployment Guide](../docs/manual-argocd-deployment.md)**

The manual deployment uses the production-ready values file located at [`argocd/manual/argocd-prod-values.yaml`](manual/argocd-prod-values.yaml), which includes:

- High availability configuration with Redis HA
- Autoscaling for repo-server and API server
- HTTPS ingress with cert-manager integration
- OIDC authentication setup (Keycloak example)
- RBAC policies for multi-tenancy

### 2. Automated Deployment (Terraform)

Deploy Argo CD automatically using Terraform for infrastructure-as-code management. This approach is ideal for:

- Production environments
- Repeatable deployments across multiple clusters
- Integration with existing Terraform infrastructure
- Team collaboration with version-controlled infrastructure

**📖 [Automated Deployment Guide](#)** *(Coming soon)*

The automated deployment is located in the [`argocd/terraform/`](terraform) directory and provides:

- Declarative infrastructure-as-code
- Automated dependency management (cert-manager, ingress controller)
- Environment-specific configurations (dev, prod)
- Integration with GCP/GKE infrastructure

