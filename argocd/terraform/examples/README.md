# Configuration Examples

Pre-configured examples for common Argo CD agent deployment scenarios.

## Available Examples

### 1. Multi-Cluster Setup (production-multi-cluster-setup.tfvars)

Deploy Argo CD Principal on a control plane cluster with agents on 3 geographically distributed workload clusters.

**Clusters**:
- Control Plane: production-cp
- Workload US-East: prod-us-east
- Workload US-West: prod-us-west
- Workload EU: prod-eu

**Features**:
- 3x controller replicas (HA)
- 3x repo server replicas (HA)
- All agents use mTLS
- Production labels and annotations

**Usage**:
```bash
cp examples/multi-cluster-setup.tfvars terraform.tfvars
# Edit terraform.tfvars with your actual cluster contexts and addresses
terraform init
terraform plan
terraform apply
```

### 2. High Availability Setup (high-availability.tfvars)

Deploy Argo CD with high availability configuration on control plane and workload clusters.

**Features**:
- 3x application controller replicas
- 3x repo server replicas
- Single workload cluster with agent
- mTLS enabled
- SLA annotations (99.9%)

**Usage**:
```bash
cp examples/high-availability.tfvars terraform.tfvars
# Edit terraform.tfvars with your cluster details
make init
make plan
make apply
```

## How to Use Examples

### Step 1: Copy Example
```bash
cp examples/<example-name>.tfvars terraform.tfvars
```

### Step 2: Customize
Edit `terraform.tfvars`:
- Update `context_name` to match your kubectl contexts
- Update `server_address` to your domain
- Adjust replica counts as needed
- Modify labels and annotations

### Step 3: Deploy
```bash
# Option 1: Using scripts
./scripts/deploy.sh

# Option 2: Using Make
make all

# Option 3: Using Terraform directly
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

### Step 4: Verify
```bash
./scripts/verify.sh
# or
make verify
```

## Customization Tips

### Get Your Kubectl Contexts
```bash
kubectl config get-contexts
```

### Get Your Cluster Addresses
```bash
kubectl cluster-info
```

### Test Network Connectivity
```bash
kubectl run -it --rm debug --image=busybox --restart=Never -- \
  nslookup argocd-cp.local
```

### Verify Certificates
```bash
openssl verify -CAfile certs/ca.crt certs/argocd-server.crt
```

## Variables Reference

### Control Plane Cluster

```hcl
control_plane_cluster = {
  name            = "cluster-name"                    # Friendly name
  context_name    = "kubectl-context"                # From `kubectl config get-contexts`
  kubeconfig_path = "~/.kube/config"                 # Path to kubeconfig
  server_address  = "argocd.example.com"             # Domain/IP for agents to reach
  server_port     = 443                              # Port for gRPC communication
  tls_enabled     = true                             # Enable mTLS
}
```

### Workload Clusters

```hcl
workload_clusters = [
  {
    name              = "cluster-name"                # Friendly name
    context_name      = "kubectl-context"            # From `kubectl config get-contexts`
    kubeconfig_path   = "~/.kube/config"             # Path to kubeconfig
    principal_address = "argocd.example.com"         # Control plane address
    principal_port    = 443                          # Control plane port
    agent_name        = "agent-name"                 # Unique agent identifier
    tls_enabled       = true                         # Enable mTLS
  }
]
```

### TLS Configuration

```hcl
tls_config = {
  generate_certs     = true          # Generate self-signed certs
  cert_validity_days = 365           # Certificate validity in days
  tls_algorithm      = "RSA"         # Algorithm (RSA or ECDSA)
}
```

### Scaling Options

```hcl
controller_replicas    = 1    # Increase to 3+ for HA
repo_server_replicas   = 1    # Increase to 3+ for HA
agent_mode             = "autonomous"  # or "managed"
server_service_type    = "LoadBalancer" # or "ClusterIP"
```

## Troubleshooting Examples

### Issue: Agents not connecting

Check the example context names match your actual contexts:
```bash
kubectl config get-contexts
```

### Issue: Certificate errors

Verify certificate path is correct:
```bash
ls -la certs/
openssl x509 -in certs/argocd-server.crt -text -noout
```

### Issue: Network connectivity

Verify DNS resolution from agent:
```bash
kubectl exec -it <agent-pod> -n argocd -- \
  nslookup <server-address>
```

## Creating Your Own Example

1. Copy an existing example
2. Modify variables for your use case
3. Test with `terraform plan`
4. Document the changes
5. Store in version control

## Best Practices

- ✅ Start with simple single-workload setup
- ✅ Test in non-production first
- ✅ Use meaningful names for clusters and agents
- ✅ Keep secrets in .gitignore
- ✅ Version control your configurations
- ✅ Document all customizations
- ✅ Backup Terraform state
- ✅ Rotate certificates annually

## Additional Resources

- [../README.md](../README.md) - Main Terraform documentation
- [../SETUP_GUIDE.md](../SETUP_GUIDE.md) - Complete setup guide
- [../scripts/README.md](../scripts/README.md) - Helper scripts
- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
