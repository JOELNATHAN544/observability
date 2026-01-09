# Argo CD Agent Setup with Terraform

Automate the complete installation and configuration of Argo CD with agent deployment on Kubernetes clusters using Terraform.

## 🎯 Overview

This Terraform configuration provides:

- **Multi-Cluster Support**: Control plane + workload cluster(s)
- **Automated mTLS**: Self-signed certificate generation for secure communication
- **Production-Ready**: High availability configuration options
- **Full Automation**: Scripts for deployment, verification, and troubleshooting
- **Comprehensive Documentation**: Setup guides and best practices

## 📋 Prerequisites

### Required Tools
- Terraform 1.0+
- kubectl with configured contexts
- Helm 3+
- OpenSSL (for certificates)
- Bash 4.0+ (for helper scripts)

### Kubernetes Requirements
- 2+ Kubernetes clusters with kubectl access
- Minimum 4GB RAM per cluster
- 10GB persistent storage (configurable)
- RBAC enabled

### Access
- kubeconfig files for both clusters
- kubectl contexts configured
- Network connectivity between clusters

## 🚀 Quick Start

### 1. Clone and Navigate

```bash
cd /Users/gis/progl/mapp7/project/observability/argocd/terraform
```

### 2. Configure

Copy the example configuration:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your cluster details:

```hcl
control_plane_cluster = {
  name            = "control-plane"
  context_name    = "your-cp-context"
  kubeconfig_path = "~/.kube/config"
  server_address  = "argocd.example.com"
  server_port     = 443
  tls_enabled     = true
}

workload_clusters = [
  {
    name              = "workload-1"
    context_name      = "your-wl-context"
    kubeconfig_path   = "~/.kube/config"
    principal_address = "argocd.example.com"
    principal_port    = 443
    agent_name        = "agent-1"
    tls_enabled       = true
  }
]
```

### 3. Deploy

**Using the automated script (recommended):**
```bash
./scripts/deploy.sh
```

**Using Terraform directly:**
```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### 4. Verify

```bash
./scripts/verify.sh
```

## 📁 Project Structure

```
terraform/
├── README.md                      # This file
├── SETUP_GUIDE.md                # Detailed setup guide
├── versions.tf                    # Terraform version & providers
├── providers.tf                   # Provider configuration
├── variables.tf                   # Input variables
├── control_plane.tf               # Control plane setup
├── workload_cluster.tf            # Workload cluster agent
├── certificates.tf                # mTLS certificate generation
├── outputs.tf                     # Output values
├── terraform.tfvars.example       # Configuration template
├── .gitignore                     # Git ignore rules
├── scripts/                       # Helper scripts
│   ├── deploy.sh                 # Deployment automation
│   ├── verify.sh                 # Verification checks
│   ├── troubleshoot.sh           # Troubleshooting tool
│   └── README.md                 # Scripts documentation
├── values/                        # Helm values (if using)
└── certs/                        # Generated certificates (git-ignored)
```

## 🔧 Configuration

### Essential Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `argocd_namespace` | `argocd` | Kubernetes namespace |
| `argocd_version` | `7.0.0` | Argo CD Helm chart version |
| `server_service_type` | `LoadBalancer` | Service type (LoadBalancer/ClusterIP/NodePort) |
| `controller_replicas` | `1` | App controller replicas |
| `repo_server_replicas` | `1` | Repo server replicas |
| `agent_mode` | `autonomous` | Agent mode (autonomous/managed) |

### TLS Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `create_certificate_authority` | `true` | Generate self-signed CA |
| `cert_validity_days` | `365` | Certificate validity period |
| `tls_algorithm` | `RSA` | TLS algorithm |

### Control Plane

```hcl
control_plane_cluster = {
  name            = "control-plane"
  context_name    = "docker-desktop"
  kubeconfig_path = "~/.kube/config"
  server_address  = "argocd-cp.local"
  server_port     = 443
  tls_enabled     = true
}
```

### Workload Clusters

```hcl
workload_clusters = [
  {
    name              = "workload-1"
    context_name      = "docker-desktop-workload"
    kubeconfig_path   = "~/.kube/config"
    principal_address = "argocd-cp.local"
    principal_port    = 443
    agent_name        = "agent-1"
    tls_enabled       = true
  }
]
```

## 🎬 Common Operations

### Deploy Everything

```bash
terraform init && terraform apply
```

### Plan Changes

```bash
terraform plan
```

### Apply Configuration

```bash
terraform apply
```

### Verify Setup

```bash
./scripts/verify.sh
```

### Check Status

```bash
kubectl get pods -A
```

### View Logs

```bash
# Agent logs
kubectl logs -n argocd deployment/argocd-agent -f
```

### Destroy Resources

```bash
terraform destroy
```

## 📊 Outputs

After deployment, view key information:

```bash
# All outputs
terraform output

# Specific output
terraform output principal_server_address

# JSON format
terraform output -json | jq '.principal_server_address.value'
```

### Key Outputs

- `principal_server_address`: Agent connection address
- `principal_server_port`: Agent connection port
- `principal_tls_enabled`: mTLS status
- `agent_name`: Agent identifier
- `ca_certificate_path`: CA certificate location
- `verification_commands`: Ready-to-use kubectl commands

## 🔒 Security Features

### mTLS (Mutual TLS)
- ✅ Encrypted communication between principal and agent
- ✅ Mutual authentication with certificates
- ✅ Certificate validation with CA

### RBAC
- ✅ Service accounts for all components
- ✅ Cluster roles and bindings
- ✅ Least privilege access

### Network Security
- ✅ Namespace isolation
- ✅ Network policies (optional)
- ✅ Restricted API access

## 🔍 Verification

### Check Deployment Status

```bash
./scripts/verify.sh
```

### Manual Verification

```bash
# Check pods
kubectl get pods -n argocd

# Check services
kubectl get svc -n argocd

# Check secrets
kubectl get secrets -n argocd

# View logs
kubectl logs -n argocd deployment/argocd-agent

# Describe pod for events
kubectl describe pod -n argocd <pod-name>
```

## 🚨 Troubleshooting

### Agent Not Connecting

```bash
./scripts/troubleshoot.sh
# Select option 1 (Agent logs)

# Or check directly
kubectl logs -n argocd deployment/argocd-agent -f
```

### Network Issues

```bash
./scripts/troubleshoot.sh
# Select option 4 (Network connectivity)

# Manual test
kubectl exec -it <agent-pod> -n argocd -- \
  nslookup argocd-cp.local
```

### Certificate Problems

```bash
./scripts/troubleshoot.sh
# Select option 5 (Certificate validity)

# Verify chain
openssl verify -CAfile certs/ca.crt certs/argocd-server.crt
```

### Full Diagnostic

```bash
./scripts/troubleshoot.sh
# Select option 9 (Full diagnostic report)
```

## 📈 Scaling

### Enable High Availability

```bash
terraform apply \
  -var 'controller_replicas=3' \
  -var 'repo_server_replicas=3'
```

### Add More Agents

Edit `workload_clusters` in `terraform.tfvars`:

```hcl
workload_clusters = [
  { ... existing config ... },
  {
    name              = "workload-2"
    context_name      = "cluster-2"
    kubeconfig_path   = "~/.kube/config"
    principal_address = "argocd-cp.local"
    principal_port    = 443
    agent_name        = "agent-2"
    tls_enabled       = true
  }
]
```

Then apply:
```bash
terraform apply
```

## 🔄 Certificate Rotation

### Rotate Certificates

```bash
# Extend validity
terraform apply -var 'tls_config.cert_validity_days=730'

# Or regenerate
rm -rf certs/
terraform apply
```

## 📚 Additional Resources

- [SETUP_GUIDE.md](SETUP_GUIDE.md) - Comprehensive setup guide
- [scripts/README.md](scripts/README.md) - Helper scripts documentation
- [Argo CD Docs](https://argo-cd.readthedocs.io/)
- [Argo CD Agent Docs](https://argocd-agent.readthedocs.io/)

## 💡 Best Practices

### Security
- Always use mTLS in production
- Rotate certificates every 6-12 months
- Store state files securely
- Limit kubeconfig access

### Operations
- Use meaningful agent names
- Tag all resources with labels
- Monitor agent connectivity
- Keep backups of Terraform state

### Development
- Test in non-prod first
- Use consistent naming conventions
- Document custom configurations
- Version control your tfvars

## 🐛 Common Issues

### "Context not found"
Ensure kubectl context names match your kubeconfig:
```bash
kubectl config get-contexts
```

### "Cannot connect to principal"
Check DNS and network connectivity:
```bash
./scripts/troubleshoot.sh
# Select option 4
```

### "Certificate validation failed"
Verify CA certificate is distributed:
```bash
./scripts/troubleshoot.sh
# Select option 5
```

## 📞 Support

### Get Help
1. Check logs: `make logs`
2. Run verification: `make verify`
3. Run diagnostics: `./scripts/troubleshoot.sh`
4. Review SETUP_GUIDE.md
5. Check Argo CD documentation

### Reporting Issues
- Include Terraform output: `terraform output -json`
- Include pod logs: `kubectl logs -n argocd <pod>`
- Include kubectl describe: `kubectl describe pod -n argocd <pod>`
- Include Terraform version: `terraform version`

## 📝 License

This Terraform configuration follows the same license as Argo CD.

## 🤝 Contributing

Improvements and fixes are welcome! Please:
1. Test changes locally
2. Update documentation
3. Follow existing code style
4. Create a pull request

---

**Last Updated**: 2025-01-09
**Terraform Version**: 1.0+
**Argo CD Version**: 7.0.0+
