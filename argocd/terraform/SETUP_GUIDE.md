# Argo CD Agent Setup with mTLS on Kubernetes

This Terraform configuration automates the complete setup of Argo CD with agent deployment on Kubernetes, including mutual TLS (mTLS) authentication between principal and agent components.

## Architecture Overview

### Components
- **Control Plane Cluster**: Runs the Argo CD Principal (server)
- **Workload Cluster(s)**: Runs the Argo CD Agent(s)
- **mTLS**: Secure encrypted communication between Principal and Agent

### TLS Flow
```
Workload Agent (with client cert)
         |
      [mTLS]
         |
    Control Plane Principal (with server cert)
         |
    CA Certificate (validates both)
```

## Prerequisites

1. **Kubernetes Clusters**
   - At least 2 clusters (control plane + workload)
   - kubectl configured with contexts
   - Helm 3.x installed

2. **Terraform**
   - Terraform 1.0+
   - Providers: kubernetes, helm, tls, local

3. **Tools**
   - kubectl
   - helm
   - openssl (for certificate verification)

## Configuration Steps

### 1. Prepare Your Environment

```bash
cd /Users/gis/progl/mapp7/project/observability/argocd/terraform

# Install dependencies
terraform init
```

### 2. Create terraform.tfvars

Copy and customize the example:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your cluster details:

```hcl
control_plane_cluster = {
  name            = "control-plane"
  context_name    = "your-cp-context"      # kubectl context name
  kubeconfig_path = "~/.kube/config"
  server_address  = "argocd.example.com"   # FQDN or IP
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

### 3. Plan the Deployment

```bash
terraform plan -out=tfplan
```

Review the output to ensure all resources will be created correctly.

### 4. Apply the Configuration

```bash
terraform apply tfplan
```

This will:
- ✅ Generate self-signed certificates for mTLS
- ✅ Create namespaces on both clusters
- ✅ Install Argo CD on control plane with TLS enabled
- ✅ Install Argo CD on workload cluster
- ✅ Deploy the Argo CD Agent with mTLS configuration
- ✅ Configure RBAC for agent operations

### 5. Verify the Setup

```bash
# Check control plane
terraform output verification_commands | head -20

# Manual verification
kubectl get pods -n argocd --context=<control-plane-context>
kubectl get pods -n argocd --context=<workload-context>

# Check agent connection
kubectl logs -n argocd -f deployment/argocd-agent --context=<workload-context>
```

## Outputs

After successful deployment, Terraform provides:

- **principal_server_address**: Agent connection address
- **principal_server_port**: Agent connection port
- **principal_tls_enabled**: Whether mTLS is active
- **agent_name**: Registered agent identifier
- **ca_certificate_path**: CA cert location
- **server_certificate_path**: Server cert location
- **agent_client_certificate_path**: Client cert location
- **verification_commands**: Pre-built kubectl commands

### View Outputs

```bash
terraform output principal_server_address
terraform output connection_commands
```

## Certificate Management

### Certificates Generated

1. **CA Certificate** (`certs/ca.crt`, `certs/ca.key`)
   - Root authority for all certificates
   - Validity: 365 days (configurable)

2. **Server Certificate** (`certs/argocd-server.crt`, `certs/argocd-server.key`)
   - Used by Principal server
   - Includes DNS names for service resolution

3. **Client Certificate** (`certs/agent-client.crt`, `certs/agent-client.key`)
   - Used by Agent for authentication
   - Presented during mTLS handshake

### Rotating Certificates

```bash
# Update certificate validity
terraform apply -var 'tls_config.cert_validity_days=730'

# Remove old certificates
rm -rf certs/
terraform apply
```

## Troubleshooting

### Agent Connection Issues

```bash
# Check agent logs
kubectl logs -n argocd deployment/argocd-agent \
  --context=<workload-context> -f

# Expected output should show successful connection to principal
```

### TLS Verification Issues

```bash
# Check certificate details
openssl x509 -in certs/argocd-server.crt -text -noout

# Verify CA chain
openssl verify -CAfile certs/ca.crt certs/argocd-server.crt
```

### Principal Not Reachable

```bash
# Check service exposure
kubectl get svc -n argocd --context=<control-plane-context>

# Port-forward for testing
kubectl port-forward -n argocd svc/argocd-server 8443:443 \
  --context=<control-plane-context>
```

## Customization

### Variables

Edit variables in `variables.tf`:

- **argocd_version**: Argo CD Helm chart version
- **server_service_type**: LoadBalancer, ClusterIP, or NodePort
- **controller_replicas**: Number of controller instances
- **agent_mode**: "autonomous" (default) or "managed"

### Enable High Availability

```bash
terraform apply \
  -var 'controller_replicas=3' \
  -var 'repo_server_replicas=3'
```

### Use Existing Certificates

Set `create_certificate_authority = false` in variables and provide:
- `certs/ca.crt` and `certs/ca.key`
- `certs/argocd-server.crt` and `certs/argocd-server.key`
- `certs/agent-client.crt` and `certs/agent-client.key`

## Clean Up

```bash
# Destroy all resources
terraform destroy

# Confirm the action when prompted
```

This will:
- Remove Argo CD installations
- Delete namespaces
- Clean up certificates (keep in backup)
- Remove Kubernetes secrets

## Best Practices

### Security
- ✅ Always use TLS in production
- ✅ Rotate certificates regularly
- ✅ Use strong CA keys
- ✅ Store certificates in secure location
- ✅ Limit access to kubeconfig files

### Operations
- ✅ Use meaningful agent names
- ✅ Tag all resources with labels
- ✅ Monitor agent connectivity
- ✅ Backup Terraform state
- ✅ Test in non-prod first

### Scalability
- ✅ Adjust replica counts based on load
- ✅ Use persistent storage
- ✅ Monitor resource usage
- ✅ Plan for cluster growth

## Additional Resources

- [Argo CD Documentation](https://argo-cd.readthedocs.io/)
- [Argo CD Agent Configuration](https://argocd-agent.readthedocs.io/)
- [TLS Configuration](https://argo-cd.readthedocs.io/en/stable/operator-manual/tls/)
- [Kubernetes TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)

## Support

For issues or questions:
1. Check logs: `kubectl logs -n argocd <pod-name>`
2. Verify connectivity: Test DNS and network paths
3. Review Terraform state: `terraform state show`
4. Check Argo CD issues: https://github.com/argoproj/argo-cd/issues
