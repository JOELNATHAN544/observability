# ArgoCD Agent Terraform - RBAC and SSO Configuration Guide

## Overview

This guide covers Role-Based Access Control (RBAC) and Keycloak Single Sign-On (SSO) integration for the ArgoCD Hub-and-Spoke architecture.

## Table of Contents

- [RBAC Architecture](#rbac-architecture)
- [Keycloak Integration](#keycloak-integration)
- [Default RBAC Groups](#default-rbac-groups)
- [Custom RBAC Policies](#custom-rbac-policies)
- [Project-Based Access Control](#project-based-access-control)
- [CLI SSO Login](#cli-sso-login)
- [Troubleshooting](#troubleshooting)

---

## RBAC Architecture

### Hub Cluster RBAC

The Agent Principal requires specific permissions to manage applications across spoke namespaces:

```yaml
# ClusterRole for cross-namespace access
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argocd-agent-principal
rules:
- apiGroups: ["argoproj.io"]
  resources: ["applications", "applicationsets", "appprojects"]
  verbs: ["get", "list", "watch", "update", "patch"]

# Role in core argocd namespace (full access)
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argocd-agent-principal-core
  namespace: argocd
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]

# Role in each agent namespace
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argocd-agent-principal
  namespace: agent-1  # Repeated for each spoke
rules:
- apiGroups: ["argoproj.io"]
  resources: ["applications", "appprojects"]
  verbs: ["get", "list", "watch", "update", "patch"]
```

### Spoke Cluster RBAC

Agents run with full permissions in their local `argocd` namespace:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: argocd-agent
  namespace: argocd
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
```

**Note**: Terraform automatically creates all required RBAC resources. This is for reference only.

---

## Keycloak Integration

### Prerequisites

Before enabling Keycloak integration:

1. **Keycloak Instance**: Running and accessible from Hub cluster
2. **Admin Credentials**: For client/user creation
3. **DNS/TLS**: ArgoCD UI must be accessible via HTTPS with a hostname

### Configuration Variables

Enable Keycloak integration in `terraform.tfvars`:

```hcl
# Enable Keycloak SSO
enable_keycloak = true

# Keycloak server details
keycloak_url      = "https://keycloak.example.com"
keycloak_realm    = "argocd"
keycloak_user     = "admin"
keycloak_password = var.keycloak_password  # Use env var: TF_VAR_keycloak_password

# ArgoCD details
argocd_url        = "https://argocd.example.com"
keycloak_client_id = "argocd"

# Authentication method
keycloak_enable_pkce = false  # See "CLI SSO Login" section below
```

**Security Best Practice**: Never commit `keycloak_password` to version control. Use environment variables:

```bash
export TF_VAR_keycloak_password="your-admin-password"
terraform apply
```

### What Terraform Configures Automatically

When `enable_keycloak = true`, Terraform creates:

1. **Keycloak Realm** (if not exists): `argocd`
2. **Keycloak Client**: `argocd` with appropriate redirect URIs
3. **Default Groups**:
   - `ArgoCDAdmins` - Full administrator access
   - `ArgoCDDevelopers` - Application deployment/sync permissions
   - `ArgoCDViewers` - Read-only access
4. **ArgoCD ConfigMap**: OIDC configuration
5. **RBAC Policy**: Group-to-role mappings

### Keycloak Client Configuration

The Terraform module creates a client with these settings:

| Setting | Value | Purpose |
|---------|-------|---------|
| Client ID | `argocd` | Identifier in OIDC flow |
| Client Protocol | `openid-connect` | Standard OIDC |
| Access Type | `confidential` (default) or `public` (PKCE) | Authentication method |
| Valid Redirect URIs | `https://argocd.example.com/*` | Callback after login |
| Base URL | `https://argocd.example.com` | ArgoCD UI |
| Root URL | `https://argocd.example.com` | Root redirect |

**Client Secret**: Auto-generated and stored in ArgoCD secret `argocd-secret` as `oidc.keycloak.clientSecret`

---

## Default RBAC Groups

Terraform creates three default groups with pre-configured permissions:

### ArgoCDAdmins

**Full administrative access** to ArgoCD:

**Permissions**:
- Create/delete Applications, AppProjects, Repositories
- Modify cluster settings
- Manage RBAC policies
- Access all namespaces
- Sync/delete any Application

**Use Cases**:
- Platform administrators
- DevOps team leads
- Incident responders

**ArgoCD RBAC Policy**:
```csv
g, ArgoCDAdmins, role:admin
```

### ArgoCDDevelopers

**Application deployment and management** permissions:

**Permissions**:
- Create/update/sync Applications
- View Application status and logs
- Access repositories
- **Cannot** delete AppProjects
- **Cannot** modify cluster settings
- **Cannot** manage users/RBAC

**Use Cases**:
- Application developers
- Team members deploying services
- CI/CD pipelines

**ArgoCD RBAC Policy**:
```csv
p, role:developer, applications, *, */*, allow
p, role:developer, repositories, get, *, allow
p, role:developer, clusters, get, *, allow
p, role:developer, projects, get, *, allow
p, role:developer, logs, get, *, allow
p, role:developer, exec, create, */*, deny

g, ArgoCDDevelopers, role:developer
```

### ArgoCDViewers

**Read-only access** for monitoring and auditing:

**Permissions**:
- View Applications, AppProjects, Repositories
- View sync status and health
- **Cannot** sync or modify anything
- **Cannot** access logs or exec into pods

**Use Cases**:
- Security auditors
- Management/stakeholders
- External monitoring systems

**ArgoCD RBAC Policy**:
```csv
p, role:viewer, applications, get, */*, allow
p, role:viewer, repositories, get, *, allow
p, role:viewer, clusters, get, *, allow
p, role:viewer, projects, get, *, allow

g, ArgoCDViewers, role:viewer
```

---

## Adding Users to Groups

### Via Keycloak UI

1. Navigate to Keycloak Admin Console: `https://keycloak.example.com/admin`
2. Select realm: `argocd`
3. Go to **Users** → **Add User**
4. Fill in details:
   - Username: `jane.doe`
   - Email: `jane.doe@example.com`
   - First Name: `Jane`
   - Last Name: `Doe`
5. Click **Save**
6. Set password: **Credentials** tab → **Set Password**
7. Assign to group: **Groups** tab → **Join Group** → Select `ArgoCDDevelopers`

### Via Terraform (Optional)

You can manage users via Terraform for Infrastructure-as-Code:

```hcl
# Create a user
resource "keycloak_user" "jane_doe" {
  realm_id = keycloak_realm.argocd.id
  username = "jane.doe"
  email    = "jane.doe@example.com"
  
  first_name = "Jane"
  last_name  = "Doe"
  
  enabled = true
  
  initial_password {
    value     = "temporary-password-123"
    temporary = true  # User must change on first login
  }
}

# Add user to group
resource "keycloak_group_memberships" "jane_developer" {
  realm_id = keycloak_realm.argocd.id
  group_id = keycloak_group.developers.id
  
  members = [
    keycloak_user.jane_doe.username,
  ]
}
```

**Note**: The Terraform module doesn't create users by default. This is for reference if you want to manage users via Terraform.

---

## Custom RBAC Policies

### Scenario 1: Team-Specific Access

**Requirement**: Development team should only access applications in `team-alpha` namespace.

**Solution**: Create custom group and policy:

1. **Create Keycloak Group**: `TeamAlpha`
2. **Add ArgoCD RBAC Policy**:

Edit `argocd-rbac-cm` ConfigMap:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    # Default policies (from Terraform)
    g, ArgoCDAdmins, role:admin
    g, ArgoCDDevelopers, role:developer
    g, ArgoCDViewers, role:viewer
    
    # Custom: TeamAlpha can only access their namespace
    p, role:team-alpha, applications, *, team-alpha/*, allow
    p, role:team-alpha, applications, get, */*, allow
    p, role:team-alpha, repositories, get, *, allow
    p, role:team-alpha, clusters, get, *, allow
    
    g, TeamAlpha, role:team-alpha
```

**Alternative (Terraform)**:

```hcl
# In hub-cluster module or custom overlay
resource "kubernetes_config_map" "argocd_rbac" {
  metadata {
    name      = "argocd-rbac-cm"
    namespace = var.hub_namespace
  }
  
  data = {
    "policy.csv" = <<-EOT
      ${local.default_rbac_policy}
      
      # Team-specific policies
      p, role:team-alpha, applications, *, team-alpha/*, allow
      p, role:team-alpha, applications, get, */*, allow
      g, TeamAlpha, role:team-alpha
    EOT
  }
}
```

### Scenario 2: Read-Only CI/CD Account

**Requirement**: CI system needs read-only access to check Application sync status.

**Solution**:

1. Create service account in Keycloak: `ci-readonly`
2. Add to `ArgoCDViewers` group
3. Generate long-lived token (or use client credentials flow)

**ArgoCD API Access**:
```bash
# Get auth token
TOKEN=$(curl -X POST \
  https://keycloak.example.com/realms/argocd/protocol/openid-connect/token \
  -d "grant_type=password" \
  -d "client_id=argocd" \
  -d "username=ci-readonly" \
  -d "password=SERVICE_ACCOUNT_PASSWORD" \
  | jq -r '.access_token')

# Check Application status
curl -H "Authorization: Bearer $TOKEN" \
  https://argocd.example.com/api/v1/applications
```

### Scenario 3: Namespace-Based Multi-Tenancy

**Requirement**: Multiple teams, each managing their own agent namespace.

**Architecture**:
```
Hub Cluster:
├── agent-team-alpha/     # Team Alpha's applications
├── agent-team-beta/      # Team Beta's applications
└── agent-team-gamma/     # Team Gamma's applications
```

**RBAC Policy**:
```csv
# Default policies
g, ArgoCDAdmins, role:admin

# Team Alpha: Full access to agent-team-alpha namespace
p, role:team-alpha-admin, applications, *, agent-team-alpha/*, allow
p, role:team-alpha-admin, projects, get, *, allow
g, TeamAlphaAdmins, role:team-alpha-admin

# Team Beta: Full access to agent-team-beta namespace
p, role:team-beta-admin, applications, *, agent-team-beta/*, allow
p, role:team-beta-admin, projects, get, *, allow
g, TeamBetaAdmins, role:team-beta-admin

# Cross-team read access (optional)
p, role:cross-team-viewer, applications, get, */*, allow
g, TeamAlphaAdmins, role:cross-team-viewer
g, TeamBetaAdmins, role:cross-team-viewer
```

---

## Project-Based Access Control

### ArgoCD AppProjects

AppProjects provide **resource-level isolation**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-alpha
  namespace: argocd
spec:
  description: Team Alpha Applications
  
  # Source repositories allowed
  sourceRepos:
  - 'https://github.com/team-alpha/*'
  
  # Destination clusters/namespaces allowed
  destinations:
  - namespace: '*'
    server: https://kubernetes.default.svc  # Spoke cluster
  
  # Cluster resource allow list
  clusterResourceWhitelist:
  - group: ''
    kind: Namespace
  - group: 'rbac.authorization.k8s.io'
    kind: Role
```

### Combining AppProjects with RBAC

```csv
# Team can only create Applications in their project
p, role:team-alpha, applications, *, team-alpha-apps/*, allow
p, role:team-alpha, applications, create, */*, deny

# But can view all projects (for collaboration visibility)
p, role:team-alpha, applications, get, */*, allow
```

---

## CLI SSO Login

ArgoCD CLI supports SSO login via Keycloak OIDC.

### PKCE Authentication (Recommended)

**Configuration**:
```hcl
keycloak_enable_pkce = true
```

**Benefits**:
- No client secret needed
- More secure for CLI/mobile apps
- Works with `argocd login --sso`

**CLI Login**:
```bash
# Login with SSO
argocd login argocd.example.com --sso

# Browser will open for Keycloak authentication
# After login, token is stored locally
```

### Client Credentials Authentication

**Configuration**:
```hcl
keycloak_enable_pkce = false  # Default
```

**CLI Login**:
```bash
# Get client secret
kubectl get secret argocd-secret -n argocd \
  -o jsonpath='{.data.oidc\.keycloak\.clientSecret}' | base64 -d

# Login with password
argocd login argocd.example.com \
  --username jane.doe \
  --password YOUR_PASSWORD
```

### Service Account / CI Login

For automation, use API tokens:

```bash
# Create API token (via UI or CLI)
argocd account generate-token --account ci-deployer

# Use token in CI
export ARGOCD_AUTH_TOKEN="argocd-token-here"
argocd app sync my-app
```

---

## Default Admin User

### Initial Access

After deployment, use the default admin account:

```bash
# Get initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

**Username**: `admin`  
**Password**: (from secret above)

### Disable Default Admin (Production)

After setting up SSO with at least one admin user:

1. Verify SSO login works
2. Disable default admin:

```bash
argocd account update-password --account admin --current-password OLD --new-password DISABLE
```

Or delete the account:

```yaml
# Patch argocd-cm
kubectl patch configmap argocd-cm -n argocd --type merge -p '
{
  "data": {
    "accounts.admin": "apiKey, login",
    "accounts.admin.enabled": "false"
  }
}
'
```

### Create Keycloak Admin User

**Terraform Variable** (optional):
```hcl
create_default_admin_user    = true
default_admin_username       = "argocd-admin"
default_admin_email          = "admin@example.com"
default_admin_password       = "ChangeMe123!"  # Use env var
default_admin_password_temporary = true  # Force change on first login
```

If enabled, Terraform creates this user in Keycloak and adds to `ArgoCDAdmins` group.

---

## Security Best Practices

### 1. Use SSO in Production

**Don't** use local admin account in production. Always configure:
- Keycloak SSO
- Multi-factor authentication (MFA) in Keycloak
- Short-lived tokens
- Regular access reviews

### 2. Principle of Least Privilege

Assign users to the **minimum required** group:
- Most users → `ArgoCDViewers` or `ArgoCDDevelopers`
- Few users → `ArgoCDAdmins`

### 3. Audit Logging

Enable ArgoCD audit logging:

```yaml
# argocd-cm ConfigMap
data:
  server.rbac.log.enforce.enable: "true"
```

Check audit logs:
```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server | grep RBAC
```

### 4. Rotate Credentials

- Keycloak admin password: Rotate quarterly
- OIDC client secret: Rotate annually
- Service account tokens: Short-lived (24h-7d)

### 5. Network Policies

Restrict ArgoCD server access:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: argocd-server-ingress
  namespace: argocd
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: argocd-server
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: ingress-nginx  # Only ingress can reach server
    ports:
    - protocol: TCP
      port: 8080
```

---

## Troubleshooting

### Issue: "Failed to verify token"

**Symptoms**: Login redirects to Keycloak but fails after authentication.

**Diagnosis**:
```bash
# Check OIDC configuration
kubectl get configmap argocd-cm -n argocd -o yaml | grep oidc

# Check ArgoCD server logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server | grep -i oidc
```

**Common Causes**:
1. **Redirect URI mismatch**: Ensure `argocd_url` matches exactly (including https://)
2. **Client secret wrong**: Check secret in `argocd-secret`
3. **Clock skew**: Ensure clocks are synced on all systems

**Fix**:
```bash
# Verify redirect URIs in Keycloak match ArgoCD URL
# Re-run Terraform to reconfigure if needed
terraform apply -replace=module.hub_cluster[0].keycloak_openid_client.argocd
```

---

### Issue: "User has no access to applications"

**Symptoms**: User logs in but sees "No applications" or permission denied errors.

**Diagnosis**:
```bash
# Check user's groups in Keycloak
# Via UI: Users → <username> → Groups

# Check RBAC policy
kubectl get configmap argocd-rbac-cm -n argocd -o yaml

# Check ArgoCD RBAC evaluation
argocd account can-i sync applications '*'
```

**Fix**:
1. Ensure user is in correct Keycloak group
2. Verify group mapping in `argocd-rbac-cm`
3. Check that group names match exactly (case-sensitive)

---

### Issue: "SSO login doesn't work in CLI"

**Symptoms**: `argocd login --sso` fails or hangs.

**Diagnosis**:
```bash
# Check if PKCE is enabled
kubectl get configmap argocd-cm -n argocd -o yaml | grep oidc
```

**Fix**:

Enable PKCE in `terraform.tfvars`:
```hcl
keycloak_enable_pkce = true
```

Apply:
```bash
terraform apply
```

---

### Issue: "Default admin password doesn't work"

**Symptoms**: Cannot login with initial admin password.

**Diagnosis**:
```bash
# Check if secret exists
kubectl get secret argocd-initial-admin-secret -n argocd

# If missing, password was changed or secret was deleted
```

**Fix**:

Reset admin password:
```bash
# Generate new password hash
NEW_PASSWORD="YourNewPassword123"
BCRYPT_HASH=$(htpasswd -nbBC 10 admin "$NEW_PASSWORD" | awk -F: '{print $2}')

# Update ArgoCD secret
kubectl patch secret argocd-secret -n argocd \
  --type='json' \
  -p="[{'op': 'replace', 'path': '/data/admin.password', 'value': '$(echo -n "$BCRYPT_HASH" | base64)'}]"

# Clear secret to force password reset
kubectl patch secret argocd-secret -n argocd \
  --type='json' \
  -p="[{'op': 'remove', 'path': '/data/admin.passwordMtime'}]"
```

---

## RBAC Policy Reference

### Policy Format

```csv
p, subject, resource, action, object, effect
g, subject, inherited_subject
```

| Field | Description | Example |
|-------|-------------|---------|
| `p` | Permission | `p` |
| `subject` | User/group/role | `role:developer` |
| `resource` | ArgoCD resource type | `applications` |
| `action` | Operation | `get`, `create`, `sync`, `*` |
| `object` | Resource identifier | `default/my-app`, `*/*, `team-alpha/*` |
| `effect` | Allow/deny | `allow`, `deny` |

| Field | Description | Example |
|-------|-------------|---------|
| `g` | Group assignment | `g` |
| `subject` | User/group | `ArgoCDDevelopers` |
| `inherited_subject` | Role to inherit | `role:developer` |

### Resource Types

- `applications` - ArgoCD Application resources
- `repositories` - Git/Helm repositories
- `clusters` - Kubernetes clusters
- `projects` - AppProjects
- `accounts` - ArgoCD user accounts
- `certificates` - TLS certificates
- `gpgkeys` - GPG signature keys
- `logs` - Pod logs
- `exec` - Pod exec access

### Actions

- `get` - View resource
- `create` - Create new resource
- `update` - Modify existing resource
- `delete` - Remove resource
- `sync` - Sync Application
- `override` - Override sync options
- `action/*` - Resource actions (restart, etc.)
- `*` - All actions

---

## Related Documentation

- [ArgoCD RBAC Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
- [Keycloak OIDC Integration](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/keycloak/)
- [ArgoCD User Management](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)
- [AppProject Specification](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/)
