# Manual Argo CD Deployment Guide

This guide walks you through manually deploying Argo CD to your Kubernetes cluster using Helm, with production-ready configurations including high availability, HTTPS ingress, and OIDC authentication.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Overview](#overview)
- [Deployment Steps](#deployment-steps)
- [Configuration Customization](#configuration-customization)
- [Verification](#verification)
- [Post-Deployment](#post-deployment)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

Before deploying Argo CD, ensure you have the following:

### Required Tools

- **kubectl**: Kubernetes command-line tool configured to access your cluster
- **helm**: Helm 3.x installed on your local machine
- **Access to Kubernetes cluster**: With sufficient permissions to create namespaces and deploy resources

### Required Infrastructure

> [!IMPORTANT]
> **Ingress Controller Required**: This deployment assumes you already have an Nginx Ingress Controller installed in your cluster. If you don't have one set up yet, please refer to the [Ingress Controller Setup Guide](./ingress-controller-setup.md) before proceeding.

- **Cert-Manager**: For automated TLS certificate management (recommended)
  - If not installed, see [Cert-Manager Setup Guide](./cert-manager-setup.md)
- **DNS Configuration**: A domain name pointing to your ingress controller's load balancer IP
- **OIDC Provider** (optional): For SSO authentication (e.g., Keycloak, Okta, Google)

---

## Overview

This deployment uses the official Argo CD Helm chart with a production-ready values file that includes:

- **High Availability**: Redis HA, multiple replicas for controller, repo-server, and API server
- **Autoscaling**: Horizontal Pod Autoscaling for repo-server and API server
- **HTTPS Ingress**: Automatic TLS certificate provisioning via cert-manager
- **OIDC Authentication**: Integration with Keycloak or other OIDC providers
- **RBAC**: Role-based access control for multi-tenancy

**Reference Configuration**: [`argocd/manual/argocd-prod-values.yaml`](../argocd/manual/argocd-prod-values.yaml)

---

## Deployment Steps

### Step 1: Create Namespace

Create a dedicated namespace for Argo CD:

```bash
kubectl create namespace argocd
```

### Step 2: Add Argo CD Helm Repository

Add the official Argo CD Helm repository:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

### Step 3: Customize the Values File

Navigate to the observability project directory and edit the Argo CD values file:

```bash
# Navigate to your observability project
cd ../argocd/manual

# Edit the values file directly
nano argocd-prod-values.yaml
```

### Step 4: Configure Your Deployment

Customize the following values in `argocd-prod-values.yaml`:

> [!WARNING]
> **Required Changes**: You MUST update these values before deployment, or the installation will fail or be misconfigured.

#### 4.1 Update Ingress Hostname

```yaml
server:
  ingress:
    hostname: "argocd.observe.camer.digital" # CHANGE THIS to your domain
    tls:
      - secretName: argocd-tls-cert
        hosts:
          - "argocd.observe.camer.digital" # CHANGE THIS to match above
```

Replace `argocd.observe.camer.digital` with your actual domain name.

#### 4.2 Update Ingress Class (if needed)

```yaml
server:
  ingress:
    ingressClassName: argocd-nginx # Verify this matches your ingress controller
```

Ensure `argocd-nginx` matches the IngressClass name of your installed Nginx Ingress Controller. You can check available IngressClasses with:

```bash
kubectl get ingressclass
```

#### 4.3 Update Cert-Manager Issuer

```yaml
server:
  ingress:
    annotations:
      cert-manager.io/cluster-issuer: "letsencrypt-prod" # CHANGE THIS to your issuer name
```

Update `letsencrypt-prod` to match your cert-manager ClusterIssuer or Issuer name. You can list available issuers with:

```bash
# For ClusterIssuers
kubectl get clusterissuer

# For namespace-scoped Issuers
kubectl get issuer -n argocd
```

If using a namespace-scoped Issuer instead of ClusterIssuer, change the annotation to:

```yaml
cert-manager.io/issuer: "your-issuer-name" # CHANGE THIS to your issuer name
```

#### 4.4 Update Argo CD URL

```yaml
configs:
  cm:
    url: https://argocd.observe.camer.digital # CHANGE THIS to your domain
```

#### 4.5 Configure OIDC (Optional)

If you're using OIDC authentication (e.g., Keycloak), you need to deploy and configure Keycloak, then integrate it with Argo CD.

> [!IMPORTANT]
> **Keycloak Deployment and Configuration Required**: Before configuring Argo CD for OIDC, you must deploy and configure Keycloak with:
> - A realm (e.g., `argocd`)
> - A client (e.g., `argocd`) with appropriate redirect URIs and client secret
> - Users and groups for authentication
> 
> For deployment and configuration instructions, see: [Keycloak Getting Started](https://www.keycloak.org/guides#getting-started) - Covers deployment and OIDC client setup for all platforms

After deploying and configuring Keycloak, update the following in the values file:

```yaml
configs:
  cm:
    oidc.config: |
      name: Keycloak
      issuer: https://keycloak.yourdomain.com/realms/argocd # CHANGE THIS TO YOUR KEYCLOAK DOMAIN ISSUER URL
      clientID: argocd # CHANGE THIS if different
      clientSecret: your-client-secret # CHANGE THIS to your Keycloak client secret
      requestedScopes: ["openid", "profile", "email", "groups"]
      enablePKCEAuthentication: true # In case you want to enable cli authentication
```

**Where to find these values in Keycloak:**
- **issuer**: `https://<keycloak-domain>/realms/<realm-name>`
- **clientID**: The client ID you created in Keycloak
- **clientSecret**: Found in Keycloak under Clients → Your Client → Credentials tab

> [!TIP]
> If you're not using OIDC authentication initially, you can remove or comment out the `oidc.config` section and use the default admin user. You can add OIDC later by updating the configuration.

### Step 5: Deploy Argo CD

Deploy Argo CD using Helm with your customized values file:

```bash
helm install argocd argo/argo-cd \
  --namespace argocd \
  --values argocd-prod-values.yaml \
  --version 7.7.12
```

> [!NOTE]
> The version `7.7.12` is specified for consistency. You can check for the latest version with `helm search repo argo/argo-cd` and update accordingly.

### Step 6: Wait for Deployment

Monitor the deployment progress:

```bash
# Watch all pods in the argocd namespace
kubectl get pods -n argocd -w

# Check deployment status
kubectl get deployments -n argocd
```

Wait until all pods are in `Running` state and all deployments show `READY` status.

---

## Configuration Customization

### Resource Limits

The reference configuration includes production-ready resource limits. Adjust these based on your cluster capacity and workload:

```yaml
controller:
  resources:
    limits:
      memory: "2Gi"
      cpu: "1"
    requests:
      memory: "512Mi"
      cpu: "250m"

repoServer:
  resources:
    limits:
      memory: "1Gi"
      cpu: "500m"
```

### Autoscaling

Autoscaling is enabled for `repoServer` and `server` components:

```yaml
repoServer:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 5

server:
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 5
```

Adjust `minReplicas` and `maxReplicas` based on your expected load.

### High Availability

Redis HA is enabled for production resilience:

```yaml
redis-ha:
  enabled: true
  exporter:
    enabled: true
```

For development environments, you can disable Redis HA to reduce resource usage:

```yaml
redis-ha:
  enabled: false
```

### RBAC Policies

Define custom RBAC policies for multi-tenancy:

```yaml
configs:
  rbac:
    policy.csv: |
      # Example: Grant 'dev-team' access only to 'dev-project'
      p, role:dev-team, applications, *, dev-project/*, allow
      g, dev-user@yourcompany.com, role:dev-team
      
      # Default admin policy
      g, admin, role:admin
      g, ArgoCDAdmins, role:admin
```

---

## Verification

### Step 1: Check Pod Status

Verify all Argo CD pods are running:

```bash
kubectl get pods -n argocd
```

Expected output should show all pods in `Running` state:

```
NAME                                                READY   STATUS    RESTARTS   AGE
argocd-application-controller-0                     1/1     Running   0          5m
argocd-applicationset-controller-xxx                1/1     Running   0          5m
argocd-dex-server-xxx                               1/1     Running   0          5m
argocd-notifications-controller-xxx                 1/1     Running   0          5m
argocd-redis-ha-haproxy-xxx                         1/1     Running   0          5m
argocd-redis-ha-server-0                            2/2     Running   0          5m
argocd-repo-server-xxx                              1/1     Running   0          5m
argocd-server-xxx                                   1/1     Running   0          5m
```

### Step 2: Check Ingress

Verify the ingress resource was created:

```bash
kubectl get ingress -n argocd
```

Check that the ingress has an address assigned:

```bash
kubectl describe ingress argocd-server -n argocd
```

### Step 3: Verify TLS Certificate

Check that cert-manager has provisioned the TLS certificate:

```bash
kubectl get certificate -n argocd
kubectl describe certificate argocd-tls-cert -n argocd
```

The certificate should show `Ready: True`.

### Step 4: Access Argo CD UI

Open your browser and navigate to your configured domain (e.g., `https://argocd.observe.camer.digital`).

You should see the Argo CD login page with HTTPS enabled.

### Step 5: Retrieve Admin Password

If not using OIDC, retrieve the initial admin password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
```

Login with:
- **Username**: `admin`
- **Password**: (output from above command)

> [!CAUTION]
> **Security Best Practice**: After logging in, immediately change the admin password or disable the admin user if using OIDC authentication.

---

## Post-Deployment

### Install Argo CD CLI

First, install the Argo CD CLI tool:

```bash
# Linux
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd
sudo mv argocd /usr/local/bin/

# macOS
brew install argocd
```

### Configure CLI Access

Login to Argo CD via CLI:

```bash
argocd login argocd.observe.camer.digital
```

You'll be prompted for username and password. Use:
- **Username**: `admin`
- **Password**: (the password retrieved in the verification step)

### Change Admin Password (Optional)

For enhanced security, you can change the admin password:

```bash
argocd account update-password
```

Alternatively, if you're using OIDC authentication, you can disable the admin user entirely:

```bash
kubectl patch configmap argocd-cm -n argocd --type merge -p '{"data":{"admin.enabled":"false"}}'
```

### Create Your First Application

Create a sample application to test Argo CD:

```bash
argocd app create guestbook \
  --repo https://github.com/argoproj/argocd-example-apps.git \
  --path guestbook \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default
```

Sync the application:

```bash
argocd app sync guestbook
```

---

## Troubleshooting

### Pods Not Starting

**Issue**: Pods stuck in `Pending` or `CrashLoopBackOff` state.

**Solutions**:
- Check resource availability: `kubectl describe pod <pod-name> -n argocd`
- Verify node resources: `kubectl top nodes`
- Check pod logs: `kubectl logs <pod-name> -n argocd`

### Ingress Not Working

**Issue**: Cannot access Argo CD UI via domain.

**Solutions**:
- Verify ingress controller is running: `kubectl get pods -n ingress-nginx` # replace by your ingress controller namespace  
- Check ingress resource: `kubectl describe ingress argocd-server -n argocd`
- Verify DNS points to load balancer IP: `nslookup argocd.yourdomain.com`
- Check ingress controller logs: `kubectl logs -n ingress-nginx <ingress-controller-pod>` # replace by your ingress controller namespace

### TLS Certificate Issues

**Issue**: Certificate not provisioning or showing as invalid.

**Solutions**:
- Check cert-manager logs: `kubectl logs -n cert-manager deployment/cert-manager` # replace by your cert-manager namespace
- Verify issuer is ready: `kubectl get clusterissuer letsencrypt-prod`
- Check certificate status: `kubectl describe certificate argocd-tls-cert -n argocd`
- Verify DNS is resolving correctly (Let's Encrypt requires public DNS)

### OIDC Authentication Failing

**Issue**: Cannot login with OIDC provider.

**Solutions**:
- Verify OIDC configuration in ConfigMap: `kubectl get configmap argocd-cm -n argocd -o yaml`
- Check client ID and secret are correct
- Verify issuer URL is accessible from the cluster
- Check Argo CD server logs: `kubectl logs -n argocd deployment/argocd-server`

### High Resource Usage

**Issue**: Argo CD consuming too many resources.

**Solutions**:
- Reduce replica counts for development environments
- Disable Redis HA if not needed
- Adjust resource limits in values file
- Disable autoscaling or adjust min/max replicas

---

## Additional Resources

- [Argo CD Official Documentation](https://argo-cd.readthedocs.io/)
- [Argo CD Helm Chart](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd)
- [Ingress Controller Setup Guide](./ingress-controller-setup.md)
- [Cert-Manager Setup Guide](./cert-manager-setup.md)
- [Automated Argo CD Deployment](#) *(Coming soon)*

---

## Next Steps

After successfully deploying Argo CD, you can:

1. **Create Projects**: Organize applications into logical projects
2. **Configure Repositories**: Connect to your Git repositories
3. **Deploy Applications**: Use Argo CD to manage your Kubernetes applications
4. **Set Up Notifications**: Configure notifications for deployment events
5. **Implement GitOps**: Adopt GitOps practices for your infrastructure

