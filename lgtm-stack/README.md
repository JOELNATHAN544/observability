# LGTM Stack Deployment

The LGTM stack is a comprehensive open-source observability platform powered by Grafana Labs. It provides correlation between metrics, logs, and traces for complete visibility into applications and infrastructure.

## Components

- **Loki**: Horizontally-scalable, highly-available, multi-tenant log aggregation system
- **Grafana**: Open observability platform for visualization and analytics
- **Tempo**: High-volume, minimal dependency distributed tracing backend
- **Mimir**: Scalable long-term storage for Prometheus metrics

## Deployment Options

### 1. Automated Deployment (Terraform)
Fully automated deployment using Terraform for infrastructure-as-code management.

For detailed instructions, see the [Terraform deployment guide](../docs/kubernetes-observability.md).

### 2. Manual Deployment (Helm)
Manual configuration and deployment for granular control over individual components.

For detailed instructions, see the [Manual deployment guide](../docs/manual-lgtm-deployment.md).

## Testing and Verification

To verify deployment correctness, see the [Testing guide](../docs/testing-monitoring-stack-deployment.md).

## Configuration

For Alloy collector configuration, see the [Alloy configuration guide](../docs/alloy-config.md).

## Adoption and Troubleshooting

### Adopting Existing Installation
To manage an existing LGTM stack with Terraform, see the [Adoption guide](../docs/adopting-lgtm-stack.md).

### Troubleshooting
For common issues and solutions, see the [Troubleshooting guide](../docs/troubleshooting-lgtm-stack.md).
