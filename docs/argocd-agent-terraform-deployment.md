# ArgoCD Agent - Terraform Deployment Guide

## Prerequisites

- Terraform >= 1.0
- Two Kubernetes clusters (Hub and Spoke) with kubeconfig access
- kubectl CLI configured
- Network connectivity from Spoke to Hub (port 8443)
- (Optional) DNS entries for ArgoCD UI and Principal
- (Optional) Keycloak instance for SSO

## Step 1: Setup

Clone the repository and navigate to the argocd-agent terraform directory:

```bash
cd /path/to/observability/argocd-agent/terraform
```

## Step 2: Configure Variables

Copy the template and edit with your values:

```bash
cp terraform.tfvars.template terraform.tfvars
```

### Minimum Required Configuration

```hcl
# Deployment mode
deploy_hub   = true
deploy_spoke = true

# Hub cluster
hub_cluster_context = "gke_project_region_hub-cluster"
hub_argocd_url      = "https://argocd.example.com"
hub_principal_host  = "agent-principal.example.com"

# Spoke cluster
spoke_cluster_context = "gke_project_region_spoke-cluster"
spoke_id             = "spoke-01"

# Email for Let's Encrypt
letsencrypt_email = "admin@example.com"
```

## Step 3: Deploy

### Initialize Terraform

```bash
terraform init
```

### Plan Deployment

```bash
terraform plan
```

Review the plan carefully. You should see:
- Hub: ArgoCD Helm release, Principal deployment, CA certificates
- Spoke: ArgoCD Helm release, Agent deployment, client certificates
- Namespaces, RBAC, secrets

### Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted.

**Deployment time**: 5-10 minutes

## Step 4: Verify Deployment

### Hub Cluster Verification

```bash
# Get Hub context from your config
export HUB_CTX="your-hub-context"

# Check pods
kubectl --context=$HUB_CTX get pods -n argocd

# Expected components:
# - argocd-server
# - argocd-agent-principal
# - argocd-redis
# - argocd-applicationset-controller
# NO argocd-application-controller (should be 0/0)

# Check Principal logs
kubectl --context=$HUB_CTX logs -n argocd deployment/argocd-agent-principal

# Verify Principal can access Redis
kubectl --context=$HUB_CTX exec -n argocd deployment/argocd-agent-principal -- \
  redis-cli -h argocd-redis ping
# Should return: PONG

# Check spoke management namespace
kubectl --context=$HUB_CTX get ns | grep spoke
```

### Spoke Cluster Verification

```bash
# Get Spoke context
export SPOKE_CTX="your-spoke-context"

# Check pods
kubectl --context=$SPOKE_CTX get pods -n argocd

# Expected components:
# - argocd-application-controller
# - argocd-repo-server
# - argocd-redis
# - argocd-agent

# Check Agent logs
kubectl --context=$SPOKE_CTX logs -n argocd deployment/argocd-agent

# Look for: "Connected to principal" (successful connection)

# Check Agent certificates
kubectl --context=$SPOKE_CTX exec -n argocd deployment/argocd-agent -- \
  ls -la /app/config/tls
# Should show: ca.crt, tls.crt, tls.key
```

## Important: Timeout Configuration

**The Terraform module automatically configures timeout settings required for the agent architecture.**

### Why Timeouts Matter

The agent architecture introduces additional latency due to the resource-proxy layer:
- API discovery requests travel: Application Controller → Resource-Proxy → Agent → Spoke Cluster
- Responses return through the same multi-hop path
- ArgoCD's default timeouts (60s repo server, 180s reconciliation) are insufficient

### Automatic Configuration

The Terraform module sets these timeouts automatically in `main.tf`:

**argocd-cmd-params-cm:**
```yaml
controller.repo.server.timeout.seconds: "300"     # 5 minutes (vs 60s default)
server.connection.status.cache.expiration: "1h"   # Cache cluster status longer
```

**argocd-cm:**
```yaml
timeout.reconciliation: "600s"        # 10 minutes (vs 180s default)
timeout.hard.reconciliation: "0"       # No hard limit
```

### Symptoms Without Proper Timeouts

If timeouts are not configured, you'll see:
- Applications stuck in "Unknown/Unknown" status
- Application controller logs showing: `failed to get api resources: the server was unable to return a response in the time allotted`
- Resource-proxy connection errors

### Verification

After deployment, verify timeout settings:

```bash
# Check controller timeouts
kubectl get configmap argocd-cmd-params-cm -n argocd -o yaml | grep timeout

# Check reconciliation timeouts
kubectl get configmap argocd-cm -n argocd -o yaml | grep timeout
```

See [Issue 9 in Troubleshooting Guide](argocd-agent-troubleshooting.md#issue-9-resource-proxy-api-discovery-timeouts) for manual configuration steps.

---

## Step 5: Test End-to-End Flow

### Create Test Application on Hub

```bash
kubectl --context=$HUB_CTX apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: spoke-01-mgmt
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps
    targetRevision: HEAD
    path: guestbook
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

### Verify on Hub

```bash
# Check Application exists
kubectl --context=$HUB_CTX get application -n spoke-01-mgmt guestbook

# Wait for sync
kubectl --context=$HUB_CTX wait --for=condition=Synced \
  application/guestbook -n spoke-01-mgmt --timeout=2m
```

### Verify on Spoke

```bash
# Application should be mirrored to Spoke
kubectl --context=$SPOKE_CTX get application -n argocd guestbook

# Resources should be deployed
kubectl --context=$SPOKE_CTX get all -n default -l app=guestbook

# Expected: deployment, service, pods
```

### Check ArgoCD UI

Access Hub ArgoCD UI at your configured URL:

```bash
# Get initial admin password
kubectl --context=$HUB_CTX -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Login and verify:
- Guestbook application appears
- Sync status is "Synced"
- Health status is "Healthy"

## Deployment Modes

### Hub-Only Deployment

Setup control plane first, add spokes later:

```hcl
deploy_hub   = true
deploy_spoke = false

hub_cluster_context = "hub-context"
hub_argocd_url      = "https://argocd.example.com"
hub_principal_host  = "agent-principal.example.com"
```

### Spoke-Only Deployment

Add additional spokes to existing Hub:

```hcl
deploy_hub   = false
deploy_spoke = true

spoke_cluster_context = "spoke-02-context"
spoke_id              = "spoke-02"

# Hub Principal endpoint (must exist)
hub_principal_host = "agent-principal.example.com"
```

**Note**: When deploying spoke-only, you need the Hub CA certificate. Store it in Terraform state from initial Hub deployment, or manually provide it.

## Multi-Spoke Scaling

### Option 1: Separate Terraform Directories

```bash
cp -r terraform spoke-02-terraform
cd spoke-02-terraform
# Edit terraform.tfvars with spoke-02 configuration
terraform init
terraform apply
```

### Option 2: Terraform Workspaces

```bash
# Create workspace for spoke-02
terraform workspace new spoke-02
terraform workspace select spoke-02

# Edit terraform.tfvars for spoke-02
terraform apply
```

### Option 3: Terraform Modules

Create a wrapper module that calls argocd-agent module multiple times with different configurations.

## Post-Deployment Configuration

### Configure Ingress DNS

Point your DNS records to the LoadBalancer IPs:

```bash
# Get ArgoCD UI LoadBalancer IP
kubectl --context=$HUB_CTX get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Get Principal LoadBalancer IP
kubectl --context=$HUB_CTX get ingress -n argocd argocd-agent-principal \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Create DNS A records:
- `argocd.example.com` → ArgoCD UI IP
- `agent-principal.example.com` → Principal IP

### Configure Keycloak SSO (Optional)

If `enable_keycloak_sso = true`, configure Keycloak OIDC client:

See [Keycloak SSO Configuration](../docs/keycloak-sso-setup.md)

## Troubleshooting

### Agent Cannot Connect to Principal

**Symptoms**: Agent logs show connection errors

**Check**:
1. DNS resolution from Spoke:
   ```bash
   kubectl --context=$SPOKE_CTX run -it --rm debug --image=curlimages/curl -- \
     nslookup agent-principal.example.com
   ```

2. Network connectivity:
   ```bash
   kubectl --context=$SPOKE_CTX run -it --rm debug --image=curlimages/curl -- \
     curl -v telnet://agent-principal.example.com:8443
   ```

3. Certificate verification:
   ```bash
   kubectl --context=$SPOKE_CTX get secret -n argocd argocd-agent-client-cert \
     -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout
   ```

### Applications Not Syncing

**Check**:
1. Agent logs for errors
2. RBAC permissions for Principal in spoke management namespace
3. Application namespace exists on Hub

See full [Troubleshooting Guide](argocd-agent-troubleshooting.md)

## Maintenance

### Certificate Rotation

Certificates are managed by Terraform. To rotate:

```bash
# Taint certificate resources
terraform taint tls_self_signed_cert.hub_ca[0]
terraform taint tls_locally_signed_cert.spoke_client[0]

# Apply to regenerate
terraform apply
```

See [PKI Management Guide](argocd-agent-pki-management.md)

### Upgrade ArgoCD Version

Update variables:

```hcl
argocd_version = "7.8.0"  # New Helm chart version
argocd_image_tag = "v2.13.0"  # New image tag
```

Apply:

```bash
terraform apply
```

Helm will perform rolling update.

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete:
- All ArgoCD installations
- All certificates
- All Applications (if managed by ArgoCD)

## Next Steps

- [Architecture Documentation](argocd-agent-architecture.md)
- [PKI Management](argocd-agent-pki-management.md)
- [Troubleshooting Guide](argocd-agent-troubleshooting.md)
