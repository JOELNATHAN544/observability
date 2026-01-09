# Helper Scripts

Automated scripts to simplify Argo CD agent deployment and management.

## Scripts Overview

### deploy.sh
**Purpose**: Automated deployment script with prerequisites check

**Usage**:
```bash
./scripts/deploy.sh
```

**What it does**:
- ✅ Validates prerequisites (terraform, kubectl, helm)
- ✅ Checks terraform.tfvars exists
- ✅ Initializes Terraform
- ✅ Validates configuration
- ✅ Creates deployment plan
- ✅ Asks for confirmation
- ✅ Applies configuration
- ✅ Shows deployment summary

### verify.sh
**Purpose**: Verify deployment and connectivity

**Usage**:
```bash
./scripts/verify.sh
```

**Checks**:
- ✅ Kubernetes contexts available
- ✅ Namespaces created
- ✅ Deployments ready
- ✅ TLS certificates valid
- ✅ Kubernetes secrets present
- ✅ Agent connectivity

### troubleshoot.sh
**Purpose**: Interactive troubleshooting tool

**Usage**:
```bash
./scripts/troubleshoot.sh
```

**Available diagnostics**:
1. View agent logs
2. View principal logs
3. Check pod events
4. Test network connectivity
5. Verify certificate validity
6. Test TLS handshake
7. List all resources
8. Show configuration
9. Full diagnostic report

## Quick Start

### Option 1: Using Scripts (Easiest)

```bash
# Deploy
./scripts/deploy.sh

# Verify
./scripts/verify.sh

# Troubleshoot if needed
./scripts/troubleshoot.sh
```

### Option 2: Using Make (Recommended)

```bash
# Initialize and deploy
make all

# Or step by step
make init
make plan
make apply
make verify
```

### Option 3: Manual Terraform

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output
```

## Troubleshooting Common Issues

### Agent not connecting

```bash
# Check logs
./scripts/troubleshoot.sh
# Select option 1 (Agent logs)

# Or manually
kubectl logs -n argocd deployment/argocd-agent -f
```

### Network connectivity issues

```bash
./scripts/troubleshoot.sh
# Select option 4 (Network connectivity)
```

### Certificate problems

```bash
./scripts/troubleshoot.sh
# Select option 5 (Certificate validity)
```

### Full diagnosis

```bash
./scripts/troubleshoot.sh
# Select option 9 (Full diagnostic report)
```

## Environment Variables

### For deploy.sh and verify.sh

```bash
# Override kubeconfig path
export KUBECONFIG=~/.kube/config

# Override kubectl context
export KUBECTL_CONTEXT=your-context
```

### For make targets

```bash
# Override cluster contexts
make verify CONTROL_PLANE_CONTEXT=cp WORKLOAD_CONTEXT=wl

# Override terraform variables
make plan TF_VARS="-var 'argocd_version=7.1.0'"
```

## Requirements

- **Unix-like environment** (Linux, macOS, WSL)
- **Bash 4.0+**
- **kubectl** configured
- **Helm 3+**
- **Terraform 1.0+**
- **openssl** (for certificate verification)
- **jq** (optional, for JSON parsing in deploy.sh)

## Tips & Tricks

### View real-time logs

```bash
# Agent logs
kubectl logs -n argocd deployment/argocd-agent -f \
  --context=<workload-context>

# Principal logs
kubectl logs -n argocd deployment/argocd-server -f \
  --context=<control-plane-context>
```

### Port forward to principal

```bash
kubectl port-forward -n argocd svc/argocd-server 8443:443 \
  --context=<control-plane-context>
```

### Check certificate details

```bash
# Expiration
openssl x509 -in certs/argocd-server.crt -noout -dates

# Subject
openssl x509 -in certs/argocd-server.crt -noout -subject

# Full details
openssl x509 -in certs/argocd-server.crt -text -noout
```

### Debug TLS connection

```bash
openssl s_client -connect argocd-cp.local:443 -showcerts
```

## Cleanup

```bash
# Cleanup just Terraform
make clean

# Also remove certificates
rm -rf certs/

# Full cleanup
terraform destroy
rm -rf certs/
make clean
```

## Support

For detailed information, see:
- `../SETUP_GUIDE.md` - Complete setup guide
- `terraform output` - Current configuration
- `kubectl get events -n argocd` - Kubernetes events
