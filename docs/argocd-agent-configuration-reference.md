# ArgoCD Agent Configuration Reference

**Version**: ArgoCD Agent v0.5.3+  
**Last Updated**: 2026-01-23

This document provides a comprehensive reference for all Terraform variables used in the ArgoCD Agent deployment.

---

## Table of Contents

- [Quick Start](#quick-start)
- [Configuration Categories](#configuration-categories)
- [Deployment Control](#deployment-control)
- [Cluster Configuration](#cluster-configuration)
- [ArgoCD Configuration](#argocd-configuration)
- [Exposure Configuration](#exposure-configuration)
- [External Principal](#external-principal)
- [Keycloak Integration](#keycloak-integration)
- [Resource Proxy & Agent Credentials](#resource-proxy--agent-credentials)
- [AppProject Configuration](#appproject-configuration)
- [Infrastructure Modules](#infrastructure-modules)
- [Certificate Management](#certificate-management)
- [High Availability](#high-availability)
- [Timeouts and Operational Parameters](#timeouts-and-operational-parameters)
- [Service Naming and DNS](#service-naming-and-dns)
- [Advanced Customization](#advanced-customization)
- [Complete Variable Matrix](#complete-variable-matrix)

---

## Quick Start

### Minimal Configuration

```hcl
# terraform.tfvars
hub_cluster_context = "gke_project_region_hub-cluster"

workload_clusters = {
  "agent-1" = "gke_project_region_spoke-1"
  "agent-2" = "gke_project_region_spoke-2"
}

# Ingress exposure (recommended for production)
ui_expose_method        = "ingress"
principal_expose_method = "ingress"
argocd_host             = "argocd.example.com"
principal_ingress_host  = "principal.example.com"

# Certificate issuer
cert_issuer_name = "letsencrypt-prod"
letsencrypt_email = "ops@example.com"
```

### Production Configuration with Keycloak SSO

```hcl
# terraform.tfvars
hub_cluster_context = "gke_project_region_hub-cluster"

workload_clusters = {
  "agent-1" = "gke_project_region_spoke-1"
  "agent-2" = "gke_project_region_spoke-2"
  "agent-3" = "gke_project_region_spoke-3"
}

# Exposure
ui_expose_method        = "ingress"
principal_expose_method = "ingress"
argocd_host             = "argocd.example.com"
principal_ingress_host  = "principal.example.com"

# Keycloak SSO
enable_keycloak       = true
keycloak_url          = "https://keycloak.example.com"
keycloak_realm        = "argocd"
keycloak_user         = "admin"
argocd_url            = "https://argocd.example.com"
keycloak_enable_pkce  = true  # Enables CLI SSO login

# HA Configuration
principal_replicas = 2

# Set via environment variables (sensitive)
# export TF_VAR_keycloak_password="keycloak-admin-password"
# export TF_VAR_default_admin_password="argocd-initial-password"
```

---

## Configuration Categories

Variables are organized into logical categories:

| Category | Variable Count | Purpose |
|----------|---------------|---------|
| Deployment Control | 2 | Enable/disable hub and spoke deployment |
| Cluster Configuration | 2 | Kubernetes cluster contexts |
| ArgoCD Configuration | 3 | ArgoCD version and namespaces |
| Exposure Configuration | 4 | UI and Principal service exposure methods |
| External Principal | 2 | Spoke-only deployment configuration |
| Keycloak Integration | 14 | SSO authentication setup |
| Resource Proxy | 3 | Agent credentials and resource proxy |
| AppProject Configuration | 4 | Default AppProject permissions |
| Infrastructure Modules | 13 | cert-manager and ingress-nginx |
| High Availability | 1 | Principal replica configuration |
| Timeouts | 6 | Operation timeout settings |
| Service Naming | 12 | Kubernetes resource names |

**Total Variables**: 61

---

## Deployment Control

### `deploy_hub`

**Type**: `bool`  
**Default**: `true`  
**Required**: No

Deploy hub infrastructure (ArgoCD control plane + Principal).

**Use Cases**:
- `true` - Deploy complete hub cluster with ArgoCD UI, server, and principal
- `false` - Skip hub deployment (for adding spokes to existing hub)

**Example**:
```hcl
deploy_hub = true
```

---

### `deploy_spokes`

**Type**: `bool`  
**Default**: `true`  
**Required**: No

Deploy spoke clusters (workload clusters with agents).

**Use Cases**:
- `true` - Deploy agents to all spoke clusters defined in `workload_clusters`
- `false` - Deploy hub only (useful for initial hub setup, add spokes later)

**Example**:
```hcl
deploy_spokes = true
```

**Deployment Scenarios**:

| Scenario | `deploy_hub` | `deploy_spokes` | Use Case |
|----------|--------------|-----------------|----------|
| Full Deployment | `true` | `true` | Deploy hub + all spokes in one operation |
| Hub Only | `true` | `false` | Initial hub setup, add spokes later |
| Add Spokes | `false` | `true` | Add new spokes to existing hub |
| Invalid | `false` | `false` | ❌ Not allowed - nothing to deploy |

---

## Cluster Configuration

### `hub_cluster_context`

**Type**: `string`  
**Default**: None  
**Required**: Yes

Kubernetes context for the hub cluster (control plane).

**How to Find**:
```bash
kubectl config get-contexts
```

**Format**:
- GKE: `gke_PROJECT_ID_REGION_CLUSTER_NAME`
- EKS: `arn:aws:eks:REGION:ACCOUNT:cluster/CLUSTER_NAME`
- AKS: `CLUSTER_NAME`
- Generic: `CONTEXT_NAME`

**Example**:
```hcl
hub_cluster_context = "gke_my-project_us-central1-a_hub-cluster"
```

**Validation**:
```bash
# Verify context exists and is accessible
kubectl --context=gke_my-project_us-central1-a_hub-cluster get nodes
```

---

### `workload_clusters`

**Type**: `map(string)`  
**Default**: `{}`  
**Required**: Yes (if `deploy_spokes = true`)

Map of agent names to Kubernetes contexts for spoke clusters.

**Format**: `{ "agent-name" => "kubectl-context" }`

**Agent Naming Guidelines**:
- Use lowercase alphanumeric + hyphens: `agent-1`, `spoke-prod-us-east`
- Avoid underscores or special characters
- Keep names short and descriptive
- Agent name becomes Kubernetes namespace name on hub: `{agent-name}-mgmt`

**Example**:
```hcl
workload_clusters = {
  "agent-1"           = "gke_project_us-central1_spoke-1"
  "agent-2"           = "gke_project_us-east1_spoke-2"
  "prod-us-west"      = "gke_project_us-west1_prod-cluster"
  "staging-eu-west"   = "gke_project_europe-west1_staging"
}
```

**Hub Namespaces Created**:
- Hub creates namespace `agent-1-mgmt` for spoke "agent-1"
- Applications for spoke "agent-1" deployed to `agent-1-mgmt` namespace
- Principal watches all `*-mgmt` namespaces for application changes

**Validation**:
```bash
# Verify all spoke contexts are accessible
for ctx in $(echo '${workload_clusters}' | jq -r '.[]'); do
  echo "Testing $ctx..."
  kubectl --context="$ctx" get nodes || echo "❌ Failed: $ctx"
done
```

**Limits**: No hard limit, tested with 20+ spokes. Practical limit based on cluster resources.

---

## ArgoCD Configuration

### `argocd_version`

**Type**: `string`  
**Default**: `"v0.5.3"`  
**Required**: No

ArgoCD Agent version to deploy.

**Supported Versions**:
- **Minimum**: `v0.5.3`
- **Tested**: `v0.5.3`
- **Recommended**: `v0.5.3` (latest stable as of 2026-01-23)

**Where Version is Used**:
- Principal installation manifests: `https://raw.githubusercontent.com/argoproj/argo-cd/${var.argocd_version}/manifests/core-install/kustomization-agent-principal.yaml`
- Agent installation manifests
- `argocd-agentctl` binary download

**Example**:
```hcl
argocd_version = "v0.5.3"
```

**Upgrade Path**:
1. Update `argocd_version` in terraform.tfvars
2. Run `terraform plan` to see changes
3. Run `terraform apply`
4. Monitor rollout: `kubectl rollout status -n argocd deployment/argocd-agent-principal`

⚠️ **Warning**: Always test version upgrades in non-production first.

---

### `hub_namespace`

**Type**: `string`  
**Default**: `"argocd"`  
**Required**: No

Kubernetes namespace for ArgoCD on the hub cluster.

**Example**:
```hcl
hub_namespace = "argocd"
```

**Customization**:
```hcl
hub_namespace = "gitops-control-plane"  # Custom namespace
```

**Impact**:
- All hub ArgoCD components deployed to this namespace
- PKI certificates, secrets, and configmaps created here
- Principal, server, repo-server, redis all in this namespace

**Post-Deployment Access**:
```bash
kubectl --context=<hub-context> get pods -n argocd
```

---

### `spoke_namespace`

**Type**: `string`  
**Default**: `"argocd"`  
**Required**: No

Kubernetes namespace for ArgoCD on spoke clusters.

**Example**:
```hcl
spoke_namespace = "argocd"
```

**Impact**:
- All spoke ArgoCD components deployed to this namespace
- Agent, application-controller, repo-server, redis in this namespace
- Agent certificates and credentials stored here

**Best Practice**: Use the same namespace name across hub and all spokes for consistency.

---

## Exposure Configuration

### `ui_expose_method`

**Type**: `string`  
**Default**: `"ingress"`  
**Required**: No  
**Allowed Values**: `"loadbalancer"`, `"ingress"`

How to expose the ArgoCD UI to external users.

**Options**:

#### LoadBalancer
```hcl
ui_expose_method = "loadbalancer"
```

**Pros**:
- Simple setup, no additional dependencies
- Automatic IP allocation
- Works immediately after deployment

**Cons**:
- Costs $$ (cloud provider charges per LoadBalancer)
- No automatic TLS/DNS
- Requires manual DNS setup
- Exposes HTTP endpoint (less secure)

**Requirements**:
- Cloud provider with LoadBalancer support (GKE, EKS, AKS)

**Access**:
```bash
# Get LoadBalancer IP
kubectl --context=<hub-context> get svc -n argocd argocd-server

# Access via IP (HTTP)
http://<EXTERNAL-IP>
```

#### Ingress (Recommended)
```hcl
ui_expose_method = "ingress"
argocd_host      = "argocd.example.com"
```

**Pros**:
- Automatic TLS certificate via cert-manager
- DNS-based access
- Single LoadBalancer for multiple services (cost-effective)
- HTTPS by default (secure)

**Cons**:
- Requires cert-manager and ingress-nginx
- More complex setup
- Requires DNS configuration

**Requirements**:
- cert-manager installed (`install_cert_manager = true`)
- nginx-ingress installed (`install_nginx_ingress = true`)
- DNS record pointing to ingress LoadBalancer IP
- cert-manager ClusterIssuer configured

**Access**:
```bash
https://argocd.example.com
```

**Comparison**:

| Feature | LoadBalancer | Ingress |
|---------|-------------|---------|
| **Cost** | $$$ (per service) | $ (shared) |
| **TLS** | Manual | Automatic |
| **DNS** | Manual | Requires setup |
| **Setup Complexity** | Low | Medium |
| **Production Ready** | No (HTTP only) | Yes (HTTPS) |
| **Use Case** | Development, testing | Production |

---

### `principal_expose_method`

**Type**: `string`  
**Default**: `"ingress"`  
**Required**: No  
**Allowed Values**: `"loadbalancer"`, `"ingress"`, `"nodeport"`

How to expose the Principal gRPC service for agent connections.

**Options**:

#### LoadBalancer
```hcl
principal_expose_method = "loadbalancer"
```

**Best For**: Production when Ingress is unavailable or when dedicated IP is required.

**Behavior**:
- Allocates cloud LoadBalancer with external IP
- Principal accessible at `<EXTERNAL-IP>:443`
- Automatic mTLS via PKI certificates

#### Ingress
```hcl
principal_expose_method = "ingress"
principal_ingress_host  = "principal.example.com"
```

**Best For**: Production with existing ingress infrastructure.

**Requirements**:
- nginx-ingress with SSL passthrough enabled
- DNS record for `principal_ingress_host`
- cert-manager for TLS certificates

**Configuration**:
```yaml
# Ingress nginx configuration required:
nginx.ingress.kubernetes.io/ssl-passthrough: "true"
nginx.ingress.kubernetes.io/backend-protocol: "GRPCS"
```

#### NodePort
```hcl
principal_expose_method = "nodeport"
```

**Best For**: Development, testing, on-premises deployments without LoadBalancer.

**Behavior**:
- Exposes Principal on high port (30000-32767) on ALL cluster nodes
- Access via `<NODE-IP>:<NODEPORT>`
- Less secure, not recommended for production

**⚠️ Production Recommendation**: Use LoadBalancer or Ingress, avoid NodePort.

---

### `argocd_host`

**Type**: `string`  
**Default**: `""`  
**Required**: Yes (if `ui_expose_method = "ingress"`)

Hostname for ArgoCD UI Ingress.

**Example**:
```hcl
argocd_host = "argocd.example.com"
```

**DNS Setup**:
```bash
# 1. Deploy Terraform (creates Ingress)
terraform apply

# 2. Get Ingress LoadBalancer IP
kubectl --context=<hub-context> get ingress -n argocd argocd-server

# 3. Create DNS A record
argocd.example.com. IN A <INGRESS-LB-IP>

# 4. Wait for cert-manager to issue certificate (2-5 minutes)
kubectl --context=<hub-context> get certificate -n argocd

# 5. Access
https://argocd.example.com
```

**TLS Certificate**:
- Automatically issued by cert-manager
- Stored in secret: `argocd-server-tls`
- Issuer defined by `cert_issuer_name`

---

### `principal_ingress_host`

**Type**: `string`  
**Default**: `""`  
**Required**: Yes (if `principal_expose_method = "ingress"`)

Hostname for Principal gRPC Ingress.

**Example**:
```hcl
principal_ingress_host = "principal.example.com"
```

**⚠️ Critical**: Must use **SSL passthrough** (gRPC with mTLS, not HTTP).

**Ingress Configuration**:
```yaml
annotations:
  nginx.ingress.kubernetes.io/ssl-passthrough: "true"
  nginx.ingress.kubernetes.io/backend-protocol: "GRPCS"
```

**Validation**:
```bash
# Test TLS handshake
openssl s_client -connect principal.example.com:443 \
  -cert agent-client.crt -key agent-client.key
```

---

## External Principal

These variables are used **only** when deploying spokes to connect to an existing hub (`deploy_hub = false`).

### `principal_address`

**Type**: `string`  
**Default**: `""`  
**Required**: Yes (if `deploy_hub = false`)

External Principal IP/hostname for spoke-only deployments.

**How to Get**:
```bash
# From hub deployment
cd terraform/environments/prod
terraform output principal_address
```

**Example**:
```hcl
# Hub deployed separately, now deploying spokes
deploy_hub = false
deploy_spokes = true

principal_address = "34.123.45.67"  # Or "principal.example.com"
principal_port    = 443
```

---

### `principal_port`

**Type**: `number`  
**Default**: `443`  
**Required**: No

External Principal port.

**Standard Ports**:
- `443` - LoadBalancer or Ingress (standard HTTPS/gRPC)
- `30000-32767` - NodePort range

---

## Keycloak Integration

Keycloak provides enterprise-grade SSO for ArgoCD with OIDC/SAML support.

### `enable_keycloak`

**Type**: `bool`  
**Default**: `false`  
**Required**: No

Enable Keycloak OIDC authentication for ArgoCD.

**Example**:
```hcl
enable_keycloak = true
```

**What Happens When Enabled**:
1. ✅ Creates Keycloak realm (if not exists)
2. ✅ Creates OIDC client `argocd` in realm
3. ✅ Configures redirect URIs
4. ✅ Creates default admin user (optional)
5. ✅ Updates ArgoCD ConfigMap with OIDC settings
6. ✅ Updates RBAC policy to map Keycloak groups

**Requirements**:
- Keycloak instance running and accessible
- Keycloak admin credentials
- ArgoCD accessible via HTTPS with hostname

**See Also**: [RBAC.md](../argocd-agent/terraform/RBAC.md) for detailed Keycloak setup.

---

### `keycloak_url`

**Type**: `string`  
**Default**: `""`  
**Required**: Yes (if `enable_keycloak = true`)

Keycloak server URL.

**Format**: Must include protocol (`https://` or `http://`)

**Example**:
```hcl
keycloak_url = "https://keycloak.example.com"
```

**Validation**:
```bash
# Test connectivity
curl -I https://keycloak.example.com
```

**⚠️ Production**: Use HTTPS only. HTTP Keycloak is insecure.

---

### `keycloak_realm`

**Type**: `string`  
**Default**: `"argocd"`  
**Required**: No

Keycloak realm name for ArgoCD client.

**Example**:
```hcl
keycloak_realm = "argocd"
```

**Behavior**:
- Terraform creates realm if it doesn't exist
- All ArgoCD clients/users created in this realm
- Isolated from other Keycloak realms

**Multi-Tenant Setup**:
```hcl
# Separate realms for different environments
keycloak_realm = "argocd-production"  # Production
keycloak_realm = "argocd-staging"     # Staging
```

---

### `keycloak_user`

**Type**: `string`  
**Default**: `"admin"`  
**Required**: No

Keycloak admin username for API operations.

**Example**:
```hcl
keycloak_user = "admin"
```

**Permissions Required**:
- Create/manage realms
- Create/manage clients
- Create/manage users
- Manage realm settings

---

### `keycloak_password`

**Type**: `string` (sensitive)  
**Default**: `""`  
**Required**: Yes (if `enable_keycloak = true`)

Keycloak admin password.

**⚠️ Security**: NEVER commit to version control.

**Recommended Methods**:

#### Environment Variable (Best)
```bash
export TF_VAR_keycloak_password="your-keycloak-admin-password"
terraform apply
```

#### Terraform Cloud
Store as sensitive variable in Terraform Cloud workspace.

#### Encrypted tfvars
```bash
# Encrypted file
ansible-vault encrypt terraform.tfvars
ansible-vault view terraform.tfvars | terraform apply -var-file=/dev/stdin
```

---

### `argocd_url`

**Type**: `string`  
**Default**: `""`  
**Required**: Yes (if `enable_keycloak = true`)

ArgoCD URL for Keycloak redirect URIs.

**Format**: Full URL with protocol

**Example**:
```hcl
argocd_url = "https://argocd.example.com"
```

**Redirect URIs Generated**:
```
https://argocd.example.com/auth/callback
https://argocd.example.com/api/dex/callback
```

**⚠️ Important**: Must match `argocd_host` when using Ingress.

---

### `keycloak_client_id`

**Type**: `string`  
**Default**: `"argocd"`  
**Required**: No

Keycloak OIDC client ID for ArgoCD.

**Example**:
```hcl
keycloak_client_id = "argocd"
```

**Customization**:
```hcl
keycloak_client_id = "argocd-production"  # Multi-environment setup
```

---

### `keycloak_enable_pkce`

**Type**: `bool`  
**Default**: `false`  
**Required**: No

Enable PKCE (Proof Key for Code Exchange) authentication.

**Options**:

#### PKCE Enabled (`true`) - Recommended
```hcl
keycloak_enable_pkce = true
```

**Benefits**:
- ✅ CLI SSO login works: `argocd login --sso`
- ✅ More secure (no client secret needed)
- ✅ Supports public clients

**Use Case**: Production environments requiring CLI access

#### Client Authentication (`false`)
```hcl
keycloak_enable_pkce = false
```

**Behavior**:
- Uses client secret authentication
- CLI SSO won't work
- More traditional OIDC flow

**Production Recommendation**: Enable PKCE for CLI access.

**CLI Login Example**:
```bash
# With PKCE enabled
argocd login argocd.example.com --sso

# Opens browser for Keycloak auth
# Returns CLI session token
```

**See Also**: [RBAC.md - CLI SSO Login](../argocd-agent/terraform/RBAC.md#cli-sso-login)

---

### `create_default_admin_user`

**Type**: `bool`  
**Default**: `true`  
**Required**: No

Create a default admin user in Keycloak for initial ArgoCD access.

**Example**:
```hcl
create_default_admin_user = true
default_admin_username    = "argocd-admin"
default_admin_password    = "ChangeMe123!"  # Set via TF_VAR
```

**Use Cases**:
- `true` - First-time setup, need immediate access
- `false` - Using existing Keycloak users/groups

**What Gets Created**:
- Keycloak user: `default_admin_username`
- Password: `default_admin_password` (temporary if `default_admin_password_temporary = true`)
- Group membership: Added to admin groups

---

### `default_admin_username`

**Type**: `string`  
**Default**: `"argocd-admin"`  
**Required**: No

Default admin username for Keycloak.

---

### `default_admin_email`

**Type**: `string`  
**Default**: `"admin@argocd.local"`  
**Required**: No

Default admin email for Keycloak user.

---

### `default_admin_password`

**Type**: `string` (sensitive)  
**Default**: `""`  
**Required**: Yes (if `create_default_admin_user = true` and `enable_keycloak = true`)

Default admin password for Keycloak user.

**⚠️ Security**: Set via environment variable:
```bash
export TF_VAR_default_admin_password="SecurePassword123!"
```

---

### `default_admin_password_temporary`

**Type**: `bool`  
**Default**: `true`  
**Required**: No

Whether the default admin password is temporary (user must change on first login).

**Options**:
- `true` - User forced to change password on first login (more secure)
- `false` - Password is permanent

**⚠️ Production Gotcha**: Keycloak won't allow login until password is changed if `true`.

**Workaround**:
```hcl
# For automation/CI/CD
default_admin_password_temporary = false
```

**See Also**: [RBAC.md - Keycloak Production Issues](../argocd-agent/terraform/RBAC.md#troubleshooting)

---

## Resource Proxy & Agent Credentials

### `enable_resource_proxy_credentials_secret`

**Type**: `bool`  
**Default**: `true`  
**Required**: No

Store resource proxy credentials in Kubernetes secret for reference and rotation.

**Example**:
```hcl
enable_resource_proxy_credentials_secret = true
```

**What Gets Created**:
- Secret: `argocd-agent-resource-proxy-credentials` in each spoke namespace
- Contains: Agent credentials for resource-proxy authentication

**Use Cases**:
- `true` - Production (enables credential rotation, audit trail)
- `false` - Embedded credentials only (less flexible)

---

### `enable_principal_ingress`

**Type**: `bool`  
**Default**: `false`  
**Required**: No

Expose Principal via Ingress in addition to LoadBalancer.

**Use Case**: Dual exposure (LoadBalancer for stability + Ingress for DNS).

---

### `principal_ingress_host`

**Type**: `string`  
**Default**: `""`  
**Required**: Yes (if `enable_principal_ingress = true`)

Hostname for Principal Ingress.

---

## AppProject Configuration

### `enable_appproject_sync`

**Type**: `bool`  
**Default**: `true`  
**Required**: No

Enable automatic AppProject synchronization to agents (required for managed mode).

**Example**:
```hcl
enable_appproject_sync = true
```

**Behavior**:
- Principal syncs AppProjects from hub to spokes
- Agents create AppProjects on spoke clusters
- Applications inherit permissions from AppProjects

**⚠️ Required**: Must be `true` for agent managed mode to work.

---

### `appproject_default_source_namespaces`

**Type**: `list(string)`  
**Default**: `["*"]`  
**Required**: No

Default AppProject source namespaces (repositories).

**Example**:
```hcl
# Allow all repositories
appproject_default_source_namespaces = ["*"]

# Restrict to specific namespaces
appproject_default_source_namespaces = ["argocd", "gitops-repos"]
```

---

### `appproject_default_dest_server`

**Type**: `string`  
**Default**: `"*"`  
**Required**: No

Default AppProject destination server.

**Example**:
```hcl
appproject_default_dest_server = "*"  # Allow all clusters
```

---

### `appproject_default_dest_namespaces`

**Type**: `list(string)`  
**Default**: `["*"]`  
**Required**: No

Default AppProject destination namespaces.

**Example**:
```hcl
# Allow deployments to all namespaces
appproject_default_dest_namespaces = ["*"]

# Restrict to specific namespaces
appproject_default_dest_namespaces = ["production", "staging", "default"]
```

**Security Best Practice**: Restrict namespaces in production.

---

## Infrastructure Modules

### `install_cert_manager`

**Type**: `bool`  
**Default**: `false`  
**Required**: No

Install cert-manager via Terraform.

**Example**:
```hcl
install_cert_manager = true
cert_manager_version = "v1.16.2"
```

**Use Cases**:
- `true` - Fresh cluster without cert-manager
- `false` - cert-manager already installed

**Validation**:
```bash
kubectl get pods -n cert-manager
```

---

### `install_nginx_ingress`

**Type**: `bool`  
**Default**: `false`  
**Required**: No

Install nginx ingress controller via Terraform.

**Example**:
```hcl
install_nginx_ingress = true
nginx_ingress_version = "4.11.3"
```

---

### `cert_manager_version`

**Type**: `string`  
**Default**: `"v1.16.2"`  
**Required**: No

cert-manager Helm chart version.

**Tested Versions**: `v1.15.0`, `v1.16.2`

---

### `nginx_ingress_version`

**Type**: `string`  
**Default**: `"4.11.3"`  
**Required**: No

nginx-ingress Helm chart version.

---

### `cert_manager_release_name`

**Type**: `string`  
**Default**: `"cert-manager"`  
**Required**: No

Helm release name for cert-manager.

---

### `cert_manager_namespace`

**Type**: `string`  
**Default**: `"cert-manager"`  
**Required**: No

Namespace for cert-manager.

---

### `nginx_ingress_release_name`

**Type**: `string`  
**Default**: `"nginx-ingress"`  
**Required**: No

Helm release name for nginx-ingress.

---

### `nginx_ingress_namespace`

**Type**: `string`  
**Default**: `"ingress-nginx"`  
**Required**: No

Namespace for nginx-ingress.

---

### `cert_issuer_name`

**Type**: `string`  
**Default**: `"letsencrypt-prod"`  
**Required**: No

Name of the cert-manager ClusterIssuer.

**Example**:
```hcl
cert_issuer_name = "letsencrypt-prod"
```

**Pre-Requisite**: ClusterIssuer must exist before deploying.

**Create ClusterIssuer**:
```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ops@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
```

---

### `cert_issuer_kind`

**Type**: `string`  
**Default**: `"Issuer"`  
**Required**: No  
**Allowed Values**: `"Issuer"`, `"ClusterIssuer"`

Kind of cert-manager issuer.

**Options**:
- `"ClusterIssuer"` - Cluster-wide (recommended for production)
- `"Issuer"` - Namespace-scoped

---

### `letsencrypt_email`

**Type**: `string`  
**Default**: `""`  
**Required**: No

Email for Let's Encrypt certificate notifications.

**Example**:
```hcl
letsencrypt_email = "ops@example.com"
```

---

### `ingress_class_name`

**Type**: `string`  
**Default**: `"nginx"`  
**Required**: No

Ingress class name to use.

**Example**:
```hcl
ingress_class_name = "nginx"
```

**Validation**:
```bash
kubectl get ingressclass
```

---

## High Availability

### `principal_replicas`

**Type**: `number`  
**Default**: `1`  
**Required**: No  
**Allowed Range**: `1-5`

Number of Principal replicas for high availability.

**Recommendations**:
- `1` - Development, testing
- `2` - Production (minimum HA)
- `3` - Production (recommended for large deployments)

**Example**:
```hcl
principal_replicas = 2
```

**What Happens**:
- Creates `replicas: 2` in Principal deployment
- Enables PodDisruptionBudget (minAvailable: 1)
- Load balancing across replicas

**⚠️ Known Limitation**: Principal HA not fully production-tested in v0.5.3.  
**See**: [argocd-agent-known-limitations.md - Principal HA](argocd-agent-known-limitations.md#5-hub-principal-not-yet-highly-available)

---

## Timeouts and Operational Parameters

### `kubectl_timeout`

**Type**: `string`  
**Default**: `"300s"`  
**Required**: No  
**Format**: `<number>[smh]` (seconds, minutes, hours)

Timeout for kubectl wait operations (deployment rollouts, pod ready checks).

**Example**:
```hcl
kubectl_timeout = "300s"  # 5 minutes
kubectl_timeout = "10m"   # 10 minutes
kubectl_timeout = "1h"    # 1 hour
```

**Use Cases**:
- Slow clusters: Increase to `600s` or `10m`
- Fast clusters: Reduce to `120s`

---

### `namespace_delete_timeout`

**Type**: `string`  
**Default**: `"120s"`  
**Required**: No

Timeout for namespace deletion operations.

**Why Needed**: Namespaces can take time to delete when resources have finalizers.

---

### `argocd_install_retry_attempts`

**Type**: `number`  
**Default**: `5`  
**Required**: No  
**Allowed Range**: `1-10`

Number of retry attempts for ArgoCD installation (handles transient network issues).

**Example**:
```hcl
argocd_install_retry_attempts = 5
```

---

### `argocd_install_retry_delay`

**Type**: `number`  
**Default**: `15`  
**Required**: No  
**Allowed Range**: `5-60` (seconds)

Delay between ArgoCD installation retry attempts.

---

### `principal_loadbalancer_wait_timeout`

**Type**: `number`  
**Default**: `300`  
**Required**: No  
**Allowed Range**: `60-600` (seconds)

Maximum wait time for Principal LoadBalancer IP allocation.

**Example**:
```hcl
principal_loadbalancer_wait_timeout = 300  # 5 minutes
```

**Cloud Provider Times**:
- GKE: 30-90 seconds
- AWS ELB: 60-120 seconds
- Azure: 90-180 seconds

---

### `argocd_agentctl_path`

**Type**: `string`  
**Default**: `"/usr/local/bin/argocd-agentctl"`  
**Required**: No

Path to argocd-agentctl binary (installed by Terraform).

---

## Service Naming and DNS

### `argocd_server_service_name`

**Type**: `string`  
**Default**: `"argocd-server"`  
**Required**: No

Name of the ArgoCD server service.

**Customization**: Only change if you have naming conflicts.

---

### `principal_service_name`

**Type**: `string`  
**Default**: `"argocd-agent-principal"`  
**Required**: No

Name of the ArgoCD Agent Principal service.

---

### `resource_proxy_service_name`

**Type**: `string`  
**Default**: `"argocd-agent-resource-proxy"`  
**Required**: No

Name of the ArgoCD Agent resource-proxy service.

---

### `resource_proxy_port`

**Type**: `number`  
**Default**: `9090`  
**Required**: No  
**Allowed Range**: `1-65535`

Port for resource-proxy service.

---

### `argocd_repo_server_name`

**Type**: `string`  
**Default**: `"argocd-repo-server"`  
**Required**: No

Name of the ArgoCD repo-server deployment.

---

### `argocd_application_controller_name`

**Type**: `string`  
**Default**: `"argocd-application-controller"`  
**Required**: No

Name of the ArgoCD application-controller statefulset.

---

### `argocd_redis_name`

**Type**: `string`  
**Default**: `"argocd-redis"`  
**Required**: No

Name of the ArgoCD Redis deployment.

---

### `argocd_redis_network_policy_name`

**Type**: `string`  
**Default**: `"argocd-redis-network-policy"`  
**Required**: No

Name of the ArgoCD Redis NetworkPolicy.

---

### `argocd_cmd_params_cm_name`

**Type**: `string`  
**Default**: `"argocd-cmd-params-cm"`  
**Required**: No

Name of the ArgoCD command parameters ConfigMap.

---

### `argocd_cm_name`

**Type**: `string`  
**Default**: `"argocd-cm"`  
**Required**: No

Name of the main ArgoCD ConfigMap.

---

### `argocd_secret_name`

**Type**: `string`  
**Default**: `"argocd-secret"`  
**Required**: No

Name of the ArgoCD secret.

---

## Advanced Customization

**⚠️ Warning**: Variables in this section should only be changed if you have specific requirements. Default values work for 99% of deployments.

All service naming variables (`argocd_*_name`) allow customization for edge cases:
- Integration with existing ArgoCD installations
- Corporate naming standards
- Migration from other GitOps tools

**Best Practice**: Use defaults unless you have a specific requirement.

---

## Complete Variable Matrix

### By Module

| Variable | Environments/Prod | Hub Module | Spoke Module |
|----------|------------------|------------|--------------|
| `deploy_hub` | ✅ | ❌ | ❌ |
| `deploy_spokes` | ✅ | ❌ | ❌ |
| `hub_cluster_context` | ✅ | ✅ | ✅ |
| `workload_clusters` | ✅ | ✅ | ❌ |
| `clusters` | ❌ | ❌ | ✅ |
| `argocd_version` | ✅ | ✅ | ✅ |
| (remaining 55 variables...) | ✅ | ✅/✅ | ✅/✅ |

### By Requirement Level

| Requirement | Count | Variables |
|-------------|-------|-----------|
| **Required** | 2 | `hub_cluster_context`, `workload_clusters` |
| **Required (Conditional)** | 8 | Keycloak variables, Ingress hosts |
| **Optional** | 51 | All others have sensible defaults |

---

## See Also

- **[Deployment Guide](argocd-agent-terraform-deployment.md)** - Step-by-step deployment instructions
- **[RBAC Guide](../argocd-agent/terraform/RBAC.md)** - Keycloak SSO and permissions
- **[Timeouts Guide](../argocd-agent/terraform/TIMEOUTS.md)** - Why agent architecture needs extended timeouts
- **[PKI Management](argocd-agent-pki-management.md)** - Certificate management and rotation
- **[Troubleshooting Guide](argocd-agent-troubleshooting.md)** - Common issues and solutions
- **[Known Limitations](argocd-agent-known-limitations.md)** - Architectural limitations to be aware of
- **[FAQ](argocd-agent-faq.md)** - Frequently asked questions

---

**Need Help?** See [argocd-agent-faq.md](argocd-agent-faq.md) or [argocd-agent-troubleshooting.md](argocd-agent-troubleshooting.md).
