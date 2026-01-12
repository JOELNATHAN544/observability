# Kubernetes Observability Platform

Comprehensive observability and operations infrastructure for Kubernetes, integrating monitoring, logging, tracing, and automated certificate management.

## Components

**Observability Stack**
- Loki - Log aggregation
- Grafana - Metrics visualization  
- Tempo - Distributed tracing
- Mimir - Long-term metrics storage

**Operations**
- ArgoCD - GitOps continuous delivery
- Cert-Manager - Automated TLS certificates
- NGINX Ingress - Traffic routing

## Getting Started

Each component includes detailed deployment guides:

- [LGTM Stack](lgtm-stack/README.md) - Complete observability platform
- [ArgoCD](argocd/README.md) - GitOps delivery
- [Cert-Manager](cert-manager/README.md) - Certificate management  
- [Ingress Controller](ingress-controller/README.md) - Traffic routing

## Documentation

Full deployment guides and references are available in the [`docs/`](docs/) directory.
