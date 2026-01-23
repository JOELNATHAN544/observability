# Terraform Destroy - Cleanup Verification Guide

## Overview

This document describes what gets cleaned up during `terraform destroy` and how to verify complete cleanup.

## Resources Managed by Terraform

### 1. **Namespaces** ✅ Auto-Cleanup Configured

| Namespace | Managed By | Cleanup Method | Status |
|-----------|------------|----------------|--------|
| `cert-manager` | Helm + null_resource | Destroy provisioner | ✅ Automated |
| `ingress-nginx` | Helm + null_resource | Destroy provisioner | ✅ Automated |
| `argocd` | Kubernetes resource | Terraform destroy | ✅ Automated |
| `agent-1` | Kubernetes resource | Terraform destroy | ✅ Automated |
| `agent-2` | Kubernetes resource | Terraform destroy | ✅ Automated |
| `agent-3` | Kubernetes resource | Terraform destroy | ✅ Automated |

**Destroy Order:**
1. `cert-manager/namespace_cleanup` deletes CRDs, then namespace
2. `ingress-nginx/namespace_cleanup` deletes namespace
3. Kubernetes provider deletes `argocd` and agent namespaces

### 2. **Helm Releases** ✅ Auto-Cleanup Configured

| Release | Namespace | Uninstall Method | CRD Cleanup |
|---------|-----------|------------------|-------------|
| `cert-manager` | `cert-manager` | Helm uninstall + CRD delete | ✅ Destroy provisioner |
| `nginx-ingress` | `ingress-nginx` | Helm uninstall | N/A |

**Destroy Order:**
1. `helm_release.cert_manager` destroy provisioner deletes CRDs **before** uninstall
2. Helm automatically uninstalls the release
3. Namespace cleanup removes any remaining resources

### 3. **Cert-Manager CRDs** ✅ Auto-Cleanup Configured

**CRDs Deleted:**
- `certificaterequests.cert-manager.io`
- `certificates.cert-manager.io`
- `challenges.acme.cert-manager.io`
- `clusterissuers.cert-manager.io`
- `issuers.cert-manager.io`
- `orders.acme.cert-manager.io`

**Cleanup Methods (Redundant for Safety):**
1. **Primary**: `helm_release.cert_manager` destroy provisioner
2. **Secondary**: `namespace_cleanup` resource
3. Both run `kubectl delete crd <name> --ignore-not-found=true`

### 4. **GCP LoadBalancers** ⚠️ Manual Cleanup May Be Required

| Service | Type | Created By | Cleanup Method |
|---------|------|------------|----------------|
| `nginx-ingress-ingress-nginx-controller` | LoadBalancer | Helm chart | Kubernetes Service deletion |
| `argocd-agent-principal` | LoadBalancer | kubectl patch | Kubernetes Service deletion |
| `argocd-server` | LoadBalancer (optional) | kubectl patch | Kubernetes Service deletion |

**Known Issue:**
GCP LoadBalancers sometimes leave orphaned resources:
- **Forwarding rules** (format: `a<32-hex-chars>`, e.g., `aa92b15706d624ec0a4c8d001e31f874`)
- **Target pools** (same format)

**Why This Happens:**
When Terraform destroys namespaces/services, Kubernetes deletes the LoadBalancer service, but GCP may not complete the cleanup of cloud resources before Terraform exits. On the next deployment, orphaned resources can block new LoadBalancer creation.

**Manual Cleanup:**
```bash
# Use the automated cleanup script
./scripts/cleanup-gcp-lb.sh

# Or manually:
gcloud compute forwarding-rules list --project=observe-472521 --regions=europe-west3
gcloud compute forwarding-rules delete <forwarding-rule-name> --region=europe-west3 --quiet

gcloud compute target-pools list --project=observe-472521 --regions=europe-west3
gcloud compute target-pools delete <target-pool-name> --region=europe-west3 --quiet
```

### 5. **Keycloak Resources** ✅ Auto-Cleanup Configured

| Resource | Type | Cleanup Method |
|----------|------|----------------|
| `argocd` realm | Keycloak Realm | Keycloak provider destroy |
| `argocd` client | OIDC Client | Keycloak provider destroy |
| Groups | Keycloak Groups | Keycloak provider destroy |
| Users | Keycloak Users | Keycloak provider destroy |

**Note:** Keycloak resources are managed by the Terraform Keycloak provider and are automatically destroyed when you run `terraform destroy`.

### 6. **ArgoCD Components** ✅ Auto-Cleanup Configured

All ArgoCD components are deployed via `kubectl apply` using `null_resource` provisioners. When Terraform destroys these resources:

1. **Base ArgoCD** (server, repo-server, application-controller) - deleted with namespace
2. **ArgoCD Agent Principal** - deleted with namespace
3. **Agent secrets** (cluster-agent-1, cluster-agent-2, cluster-agent-3) - deleted with namespace
4. **PKI certificates** - deleted with namespace
5. **ConfigMaps** (argocd-cm, argocd-cmd-params-cm, argocd-agent-params) - deleted with namespace

## Destroy Execution Order

Terraform determines the destroy order based on resource dependencies:

```
1. Destroy Keycloak resources (realm, clients, groups, users)
   ↓
2. Destroy ArgoCD resources in hub namespace
   ↓
3. Delete agent namespaces (agent-1, agent-2, agent-3)
   ↓
4. Delete hub namespace (argocd)
   ↓
5. Uninstall Helm releases (cert-manager, nginx-ingress)
   ↓  - CRDs deleted via destroy provisioner
   ↓
6. Delete infrastructure namespaces (cert-manager, ingress-nginx)
   ↓  - Run namespace_cleanup destroy provisioners
   ↓
7. Delete Let's Encrypt Issuer resources
```

## Verification Steps

### Automated Verification

Run the verification script after `terraform destroy`:

```bash
./scripts/verify-destroy.sh
```

This checks:
- ✅ All namespaces deleted
- ✅ All Helm releases uninstalled
- ✅ All cert-manager CRDs deleted
- ✅ No orphaned GCP LoadBalancers
- ℹ️  Keycloak resources (manual check)
- ✅ ArgoCD agent secrets deleted

### Manual Verification

#### 1. Check Namespaces
```bash
kubectl get namespaces | grep -E 'argocd|agent|cert-manager|ingress-nginx'
# Expected: No output
```

#### 2. Check Helm Releases
```bash
helm list --all-namespaces
# Expected: No cert-manager or nginx-ingress releases
```

#### 3. Check CRDs
```bash
kubectl get crd | grep cert-manager
# Expected: No output
```

#### 4. Check GCP LoadBalancers
```bash
gcloud compute forwarding-rules list --project=observe-472521 --regions=europe-west3
# Expected: No orphaned rules with format a<32-hex-chars>

gcloud compute target-pools list --project=observe-472521 --regions=europe-west3
# Expected: No orphaned pools with format a<32-hex-chars>
```

#### 5. Check Keycloak
Navigate to: https://keycloak-dev.observe.camer.digital
- Verify `argocd` realm is deleted
- Verify clients, groups, and users are removed

## Troubleshooting

### Issue: Namespaces Stuck in "Terminating"

**Cause:** Finalizers on resources prevent namespace deletion

**Solution:**
```bash
# Remove finalizers from stuck namespace
kubectl get namespace <namespace> -o json | \
  jq '.spec.finalizers = []' | \
  kubectl replace --raw "/api/v1/namespaces/<namespace>/finalize" -f -

# Or use the cleanup script
./scripts/cleanup-namespaces.sh
```

### Issue: LoadBalancer Stuck in Pending on Next Deploy

**Cause:** Orphaned GCP forwarding rules/target pools

**Solution:**
```bash
# Run automated cleanup
./scripts/cleanup-gcp-lb.sh

# Then delete and recreate the service
kubectl delete svc <service-name> -n <namespace>
kubectl rollout restart deployment/<deployment-name> -n <namespace>
```

### Issue: Helm Uninstall Warnings About CRDs

**Cause:** CRDs are protected by Helm's resource policy

**Solution:**
This is **expected behavior** and handled by destroy provisioners. The warning is informational. The CRDs are deleted via:
1. `helm_release.cert_manager` destroy provisioner
2. `namespace_cleanup` destroy provisioner

No action required.

### Issue: Terraform Destroy Times Out

**Cause:** Long-running namespace deletion waiting for resources to finalize

**Solution:**
```bash
# Increase timeout
export TF_VAR_namespace_delete_timeout="300s"
terraform destroy -auto-approve

# Or manually delete stuck resources
kubectl delete all --all -n <namespace> --force --grace-period=0
```

## Complete Cleanup Checklist

After running `terraform destroy`, verify:

- [ ] All namespaces deleted: `kubectl get ns`
- [ ] All Helm releases uninstalled: `helm list -A`
- [ ] All CRDs removed: `kubectl get crd | grep cert-manager`
- [ ] No orphaned LoadBalancers: `gcloud compute forwarding-rules list`
- [ ] No orphaned target pools: `gcloud compute target-pools list`
- [ ] Keycloak realm deleted (manual check in UI)
- [ ] No ArgoCD resources: `kubectl get all -A | grep argocd`
- [ ] Run verification script: `./scripts/verify-destroy.sh`

## Scripts Reference

| Script | Purpose | When to Use |
|--------|---------|-------------|
| `verify-destroy.sh` | Verify all resources deleted | After every `terraform destroy` |
| `cleanup-namespaces.sh` | Manually delete stuck namespaces | When namespaces remain after destroy |
| `cleanup-gcp-lb.sh` | Clean orphaned GCP LoadBalancers | When LB provisioning fails on next deploy |

## Known Limitations

1. **GCP LoadBalancers**: May leave orphaned cloud resources that require manual cleanup
2. **Keycloak Verification**: Must be verified manually in Keycloak UI
3. **Finalizers**: Some resources with finalizers may cause namespace deletion delays

## Recommendations

1. **Always run verification** after `terraform destroy`:
   ```bash
   terraform destroy -auto-approve && ./scripts/verify-destroy.sh
   ```

2. **Before re-deploying**, ensure clean state:
   ```bash
   ./scripts/verify-destroy.sh
   ./scripts/cleanup-gcp-lb.sh  # If verification fails
   ```

3. **Monitor destroy progress** for long-running operations:
   ```bash
   # Watch namespace deletion
   watch kubectl get ns
   
   # Watch Helm releases
   watch helm list -A
   ```

4. **Save destroy logs** for troubleshooting:
   ```bash
   terraform destroy -auto-approve 2>&1 | tee destroy.log
   ```
