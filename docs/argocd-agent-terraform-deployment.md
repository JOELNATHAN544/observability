# ArgoCD Agent - Terraform Deployment Guide

## Prerequisites

- Terraform >= 1.0
- Kubernetes clusters (Hub and/or Spoke) with kubeconfig access
- kubectl CLI configured
- argocd-agentctl binary (for PKI operations)
- Network connectivity from Spoke to Hub (port 443 for Principal)
- (Optional) Existing cert-manager and ingress-nginx installations
- (Optional) Keycloak instance for SSO

## Architecture Overview

This deployment uses a **modular Terraform structure** with separate hub-cluster and spoke-cluster modules orchestrated through an environment-specific configuration.

```
terraform/
├── environments/
│   └── prod/              # Production environment (USE THIS)
│       ├── main.tf        # Module orchestration
│       ├── variables.tf   # Variable definitions
│       ├── terraform.tfvars.example
│       └── ...
├── modules/
│   ├── hub-cluster/       # Hub cluster module
│   └── spoke-cluster/     # Spoke cluster module
├── TIMEOUTS.md            # Timeout configuration guide
├── RBAC.md                # RBAC and SSO guide
└── README.md
```

## Step 1: Setup

Clone the repository and navigate to the production environment directory:

```bash
cd /path/to/observability/argocd-agent/terraform/environments/prod
```

## Step 2: Configure Variables

Copy the example and edit with your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

### Minimum Required Configuration

```hcl
# Deployment mode
deploy_hub    = true
deploy_spokes = true

# Hub cluster
hub_cluster_context = "gke_project_region_hub-cluster"

# Spoke clusters (map of agent_name => cluster_context)
workload_clusters = {
  "agent-1" = "gke_project_region_spoke-1"
  "agent-2" = "gke_project_region_spoke-2"
}

# ArgoCD version
argocd_version = "v0.5.3"

# Exposure method
ui_expose_method        = "loadbalancer"  # or "ingress"
principal_expose_method = "loadbalancer"  # or "ingress"

# For ingress mode, set:
# argocd_host = "argocd.example.com"
# ingress_class_name = "nginx"
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
- **Hub Module**: ArgoCD installation, Principal, PKI CA, per-agent namespaces
- **Spoke Module**: ArgoCD in agent-managed mode, agents, client certificates
- **Infrastructure**: cert-manager and ingress-nginx (if enabled)
- Namespaces, RBAC, secrets, network policies

### Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted.

**Deployment time**: 10-15 minutes (depending on number of agents)

## Step 4: Verify Deployment

### Hub Cluster Verification

```bash
# Get Hub context from your config
export HUB_CTX="your-hub-context"

# Check pods
kubectl --context=$HUB_CTX get pods -n argocd

# Expected components:
# - argocd-server (UI and API)
# - argocd-agent-principal (agent manager)
# - argocd-repo-server (for hub operations)
# - argocd-redis
# - argocd-applicationset-controller
# ❌ NO argocd-application-controller (runs on spokes)

# Check Principal logs
kubectl --context=$HUB_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent-principal

# Verify Principal can access Redis
kubectl --context=$HUB_CTX exec -n argocd deployment/argocd-repo-server -- \
  redis-cli -h argocd-redis ping
# Should return: PONG

# Check agent namespaces (one per agent)
kubectl --context=$HUB_CTX get ns | grep -E "agent-|spoke-"
# Should show: agent-1, agent-2, etc.

# Get ArgoCD outputs
terraform output
```

### Spoke Cluster Verification

```bash
# For each spoke cluster, verify:
export SPOKE_CTX="your-spoke-1-context"

# Check pods
kubectl --context=$SPOKE_CTX get pods -n argocd

# Expected components:
# - argocd-application-controller (application reconciliation)
# - argocd-repo-server (local repo server)
# - argocd-redis (local cache)
# - argocd-agent (gRPC client)

# Check Agent logs for successful connection
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent

# Look for: "connected to principal" or "agent started"

# Verify agent certificates
kubectl --context=$SPOKE_CTX get secret -n argocd argocd-agent-client-tls
kubectl --context=$SPOKE_CTX get secret -n argocd argocd-agent-ca

# Check agent connectivity to Principal
kubectl --context=$SPOKE_CTX exec -n argocd deployment/argocd-agent -- \
  curl -v https://YOUR_PRINCIPAL_ADDRESS:443/healthz
```

## Important: Timeout Configuration

**The Terraform modules automatically configure extended timeout settings required for the agent architecture.**

### Why Timeouts Matter

The agent architecture introduces additional latency due to resource-proxy communication:
- Requests travel: Application Controller → Resource-Proxy → Agent → Principal → Hub
- Default ArgoCD timeouts (60s repo server, 180s reconciliation) are insufficient
- Multi-hop communication requires extended timeout values

### Automatic Configuration

The hub-cluster module configures these timeouts automatically:

| Setting | Default | Agent Mode | Reason |
|---------|---------|------------|--------|
| `kubectl_timeout` | 60s | 300s | Deployment rollouts take longer |
| `namespace_delete_timeout` | 60s | 120s | Resource finalizers need time |
| `argocd_install_retry_attempts` | 3 | 5 | Network transients more common |
| `principal_loadbalancer_wait_timeout` | 120s | 300s | Cloud LB provisioning |

### Tuning for Your Environment

See **[TIMEOUTS.md](../argocd-agent/terraform/TIMEOUTS.md)** for:
- Detailed timeout variable documentation
- Environment-specific tuning guidelines (dev/staging/prod)
- Timeout interaction examples
- Troubleshooting timeout-related issues

### Quick Verification

```bash
# Check module-configured timeouts
cd terraform/environments/prod
terraform show | grep timeout

# Verify deployments are healthy
kubectl --context=$HUB_CTX get deployments -n argocd
kubectl --context=$SPOKE_CTX get deployments -n argocd
```

---

## Step 5: Test End-to-End Flow

### Create Test Application on Hub

Create an Application in the agent's management namespace on the Hub:

```bash
# For agent-1 (adjust namespace for your agent names)
kubectl --context=$HUB_CTX apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook
  namespace: agent-1  # This is the agent's namespace on Hub
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
# Check Application exists in agent namespace
kubectl --context=$HUB_CTX get application -n agent-1 guestbook

# Check sync status (may take a few moments)
kubectl --context=$HUB_CTX get application -n agent-1 guestbook -o jsonpath='{.status.sync.status}'
# Should show: Synced
```

### Verify on Spoke

```bash
# Application should be mirrored to spoke cluster
export SPOKE1_CTX="your-spoke-1-context"
kubectl --context=$SPOKE1_CTX get application -n argocd guestbook

# Resources should be deployed on spoke
kubectl --context=$SPOKE1_CTX get all -n default -l app.kubernetes.io/instance=guestbook

# Expected: deployment, service, pods in Running state
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

### Mode 1: Full Deployment (Hub + Multiple Spokes)

Deploy complete hub-and-spoke architecture simultaneously:

```hcl
deploy_hub    = true
deploy_spokes = true

hub_cluster_context = "hub-context"

workload_clusters = {
  "prod-agent"    = "gke_project_region_prod-cluster"
  "staging-agent" = "gke_project_region_staging-cluster"
  "dev-agent"     = "gke_project_region_dev-cluster"
}

ui_expose_method        = "loadbalancer"
principal_expose_method = "loadbalancer"
```

**Best for**: New deployments, setting up complete environments

### Mode 2: Hub-Only Deployment

Setup control plane first, add spokes later:

```hcl
deploy_hub    = true
deploy_spokes = false

hub_cluster_context = "hub-context"
workload_clusters   = {}  # Empty - no spokes yet

ui_expose_method        = "ingress"
principal_expose_method = "loadbalancer"
argocd_host             = "argocd.example.com"
```

After deployment, get the Principal address for spoke connections:
```bash
terraform output principal_address
terraform output principal_port
```

**Best for**: Phased rollouts, testing hub first

### Mode 3: Spoke-Only Deployment

Add additional spokes to existing Hub:

```hcl
deploy_hub    = false
deploy_spokes = true

hub_cluster_context = "hub-context"  # For agent operations
hub_namespace       = "argocd"

# External Principal from existing hub
principal_address = "34.89.123.45"  # From hub deployment output
principal_port    = 443

# New spokes to add
workload_clusters = {
  "new-agent-1" = "gke_project_region_new-cluster-1"
  "new-agent-2" = "gke_project_region_new-cluster-2"
}
```

**Best for**: Scaling out to additional clusters, incremental growth

## Post-Deployment Configuration

### Configure DNS (If Using LoadBalancer)

Point your DNS records to the LoadBalancer IPs:

```bash
# Get ArgoCD UI LoadBalancer IP
kubectl --context=$HUB_CTX get svc -n argocd argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Get Principal LoadBalancer IP
kubectl --context=$HUB_CTX get svc -n argocd argocd-agent-principal -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

Create DNS A records:
- `argocd.example.com` → ArgoCD UI IP
- `principal.example.com` → Principal IP

### Configure Keycloak SSO (Optional)

If `enable_keycloak = true`, the module automatically configures:
- Keycloak OIDC client for ArgoCD
- Three default groups: ArgoCDAdmins, ArgoCDDevelopers, ArgoCDViewers
- RBAC policy mappings

See **[RBAC.md](../argocd-agent/terraform/RBAC.md)** for:
- Complete Keycloak setup instructions
- User and group management
- Custom RBAC policy examples
- Project-based access control
- Security best practices

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
