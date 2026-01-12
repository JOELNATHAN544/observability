# Kubernetes Observability & Operations

A modular infrastructure-as-code repository for provisioning observability and operations platforms on Kubernetes.

## Core Platforms

**Observability (LGTM)**
[`lgtm-stack/`](lgtm-stack/README.md)
Comprehensive monitoring, logging, and tracing stack powered by Grafana, Loki, Tempo, and Mimir.

**GitOps Delivery**
[`argocd/`](argocd/README.md)
Declarative continuous delivery engine for managing cluster workloads and configurations.

## Cluster Infrastructure

**Certificate Management**
[`cert-manager/`](cert-manager/README.md)
Automated TLS certificate issuance and renewal via Let's Encrypt.

**Traffic Management**
[`ingress-controller/`](ingress-controller/README.md)
NGINX-based ingress controller for external traffic routing and load balancing.

---

## Deployment & Documentation

Detailed guides for deployment, adoption, and troubleshooting are located in the [`docs/`](docs/) directory.

- **[LGTM Deployment](docs/kubernetes-observability.md)**
- **[ArgoCD Deployment](docs/argocd-terraform-deployment.md)**
- **[Cert-Manager Deployment](docs/cert-manager-terraform-deployment.md)**
- **[Ingress Controller Deployment](docs/ingress-controller-terraform-deployment.md)**
