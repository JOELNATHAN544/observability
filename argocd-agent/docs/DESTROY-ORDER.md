# Terraform Destroy Order and Resource Cleanup

## Destroy Execution Flow

When you run `terraform destroy`, resources are destroyed in **reverse dependency order**. Here's the complete flow:

### Phase 1: Application-Level Resources
```
Keycloak Users & Groups
  ↓
Keycloak OIDC Client
  ↓
Keycloak Client Scopes
  ↓
Keycloak Realm
```

### Phase 2: ArgoCD Agent Resources (Hub)
```
Spoke Agent Creation Resources (null_resource)
  ↓
Agent Credentials Documentation (null_resource)
  ↓
Resource Proxy Verification (null_resource)
  ↓
Resource Proxy Credentials Secret (null_resource)
  ↓
Principal Restart (null_resource)
  ↓
Principal Environment Variables Config (null_resource)
  ↓
Principal Resource-Proxy Config (null_resource)
  ↓
Principal Allowed Namespaces Config (null_resource)
  ↓
PKI Certificates (principal, resource-proxy, JWT)
  ↓
Principal Installation (null_resource)
  ↓
PKI Initialization (null_resource)
  ↓
ArgoCD Configuration (reconciliation timeouts, apps-in-any-namespace)
  ↓
ArgoCD Base Installation (null_resource)
```

### Phase 3: Spoke Cluster Resources (if deployed)
```
Spoke AppProject Sync (null_resource)
  ↓
Spoke Agent Connection (null_resource)
  ↓
Spoke Agent Installation (null_resource)
  ↓
Spoke Managed ArgoCD Installation (null_resource)
```

### Phase 4: Hub Cluster Namespaces
```
Agent Managed Namespaces (agent-1, agent-2, agent-3)
  ↓  - kubernetes_namespace resources
  ↓  - All resources in namespace deleted first
  ↓
Hub ArgoCD Namespace (argocd)
  ↓  - kubernetes_namespace resource
  ↓  - ALL ArgoCD resources deleted:
  ↓    - Deployments (argocd-server, argocd-repo-server, etc.)
  ↓    - StatefulSets (argocd-application-controller)
  ↓    - Services (INCLUDING LoadBalancers)
  ↓    - ConfigMaps
  ↓    - Secrets
  ↓    - ServiceAccounts
  ↓    - Roles, RoleBindings
```

**Important**: When the `argocd` namespace is deleted, Kubernetes sends delete requests for **all services** including LoadBalancer-type services. This triggers GCP to delete cloud resources, but **the deletion happens asynchronously**.

### Phase 5: Infrastructure (Cert-Manager)

```
Let's Encrypt Issuer (null_resource)
  ↓  - Destroy provisioner: kubectl delete Issuer/ClusterIssuer
  ↓
Cert-Manager Namespace Cleanup (null_resource)
  ↓  - Destroy provisioner runs BEFORE Helm uninstall
  ↓  - Deletes all cert-manager CRDs
  ↓  - Force deletes cert-manager namespace
  ↓
Cert-Manager Helm Release
  ↓  - Destroy provisioner: Delete CRDs (redundant)
  ↓  - Helm uninstall cert-manager
  ↓  - GCP LoadBalancer deletion (if any) triggered
```

### Phase 6: Infrastructure (Ingress-Nginx)

```
Ingress-Nginx Namespace Cleanup (null_resource)
  ↓  - Destroy provisioner runs AFTER Helm uninstall
  ↓  - Force deletes ingress-nginx namespace
  ↓
Ingress-Nginx Helm Release
  ↓  - Helm uninstall nginx-ingress
  ↓  - GCP LoadBalancer deletion triggered for nginx-ingress-ingress-nginx-controller
```

### Phase 7: Terraform State Cleanup
```
All resources marked as destroyed in state
  ↓
terraform.tfstate updated
```

## LoadBalancer Cleanup Details

### Services That Create LoadBalancers

| Service | Namespace | Created By | Destroy Trigger |
|---------|-----------|------------|-----------------|
| `nginx-ingress-ingress-nginx-controller` | `ingress-nginx` | Helm chart | Helm uninstall |
| `argocd-agent-principal` | `argocd` | kubectl patch (null_resource) | Namespace deletion |
| `argocd-server` | `argocd` | kubectl patch (null_resource, optional) | Namespace deletion |

### What Happens During Destroy

1. **Terraform destroys the namespace resource**
   ```
   Destroying: kubernetes_namespace.hub_argocd
   ```

2. **Kubernetes deletes all resources in namespace**
   ```
   - Delete Deployments (triggers pod termination)
   - Delete Services (triggers LoadBalancer cleanup)
   - Delete ConfigMaps, Secrets, etc.
   ```

3. **Kubernetes sends delete request to GCP**
   ```
   - GCP receives: "Delete LoadBalancer for service X"
   - GCP starts deleting:
     * Forwarding rules
     * Target pools
     * Health checks
     * Firewall rules
   ```

4. **Terraform waits for namespace deletion**
   ```
   - Namespace enters "Terminating" state
   - Kubernetes waits for all finalizers
   - Namespace deletion completes
   - Terraform marks resource as destroyed
   ```

**The Problem**: GCP resource deletion (step 3) happens **asynchronously**. By the time Terraform exits, GCP may still be cleaning up cloud resources. If you immediately re-deploy, the old resources may still exist and block new LoadBalancer creation.

### Why Orphaned Resources Happen

**Timeline:**
```
T+0s:   Terraform: destroy kubernetes_namespace.hub_argocd
T+1s:   Kubernetes: Delete service argocd-agent-principal
T+2s:   Kubernetes → GCP: "Delete LoadBalancer XYZ"
T+3s:   GCP: Start deleting forwarding rule aa92b15706d624ec0a4c8d001e31f874
T+4s:   Kubernetes: Namespace finalizers cleared
T+5s:   Kubernetes: Namespace deleted
T+6s:   Terraform: Namespace destroy complete! ✓
T+7s:   Terraform: All resources destroyed! ✓
T+8s:   <Terraform exits>
---
T+15s:  GCP: Still deleting target pool... (but Terraform already exited)
T+20s:  GCP: Forwarding rule deletion complete
T+30s:  GCP: Target pool deletion complete
```

If you run `terraform apply` at T+10s, the old resources still exist and may cause conflicts.

## Namespace Deletion Guarantees

### Cert-Manager Namespace
✅ **Guaranteed Cleanup**
- Destroy provisioner explicitly deletes CRDs
- Destroy provisioner force-deletes namespace
- Double cleanup (Helm uninstall + namespace_cleanup)

### Ingress-Nginx Namespace
✅ **Guaranteed Cleanup**
- Destroy provisioner force-deletes namespace
- Namespace cleanup runs after Helm uninstall

### ArgoCD Namespace
✅ **Guaranteed Cleanup**
- Kubernetes provider manages deletion
- All resources deleted when namespace is destroyed
- No finalizers blocking deletion

### Agent Namespaces (agent-1, agent-2, agent-3)
✅ **Guaranteed Cleanup**
- Kubernetes provider manages deletion
- Minimal resources (mostly ArgoCD Applications)
- No blocking finalizers

## CRD Cleanup Guarantees

### Cert-Manager CRDs
✅ **Double Cleanup**
1. `helm_release.cert_manager` destroy provisioner
2. `namespace_cleanup` destroy provisioner

Both run: `kubectl delete crd <name> --ignore-not-found=true --timeout=60s`

**Redundancy ensures**: Even if one fails, the other cleans up.

## GCP Resource Cleanup

### ⚠️ LoadBalancers - Manual Verification Required

**Why**: Asynchronous cloud resource deletion

**Affected Resources**:
- Forwarding rules (format: `a<32-hex-chars>`)
- Target pools (format: `a<32-hex-chars>`)
- Backend services (if using internal LB)
- Health checks (if created)

**Verification**:
```bash
# Check for orphaned resources
gcloud compute forwarding-rules list \
  --project=observe-472521 \
  --regions=europe-west3 \
  --filter="name~'^a[a-f0-9]{31}$'"

gcloud compute target-pools list \
  --project=observe-472521 \
  --regions=europe-west3 \
  --filter="name~'^a[a-f0-9]{31}$'"
```

**Cleanup** (if needed):
```bash
# Automated
./scripts/cleanup-gcp-lb.sh

# Manual
gcloud compute forwarding-rules delete <name> --region=europe-west3 --quiet
gcloud compute target-pools delete <name> --region=europe-west3 --quiet
```

## Keycloak Resource Cleanup

### ✅ Automated via Terraform Provider

Resources destroyed by Terraform Keycloak provider:
- Realm: `argocd`
- OIDC Client: `argocd`
- Client Scopes: `groups`
- Groups: `ArgoCDAdmins`, `ArgoCDDevelopers`, `ArgoCDViewers`
- Users: `argocd-admin`

**Verification**: Check Keycloak UI at https://keycloak-dev.observe.camer.digital

## Best Practices

### 1. Always Verify After Destroy
```bash
terraform destroy -auto-approve
./scripts/verify-destroy.sh
```

### 2. Wait Before Re-Deploying
```bash
# After destroy, wait 30-60 seconds for GCP cleanup
terraform destroy -auto-approve
sleep 60
terraform apply -auto-approve
```

### 3. Clean Up Orphaned Resources
```bash
# Before re-deploying, check for orphans
./scripts/cleanup-gcp-lb.sh
```

### 4. Monitor Destroy Progress
```bash
# In another terminal
watch kubectl get ns
watch "gcloud compute forwarding-rules list --regions=europe-west3"
```

### 5. Save Destroy Logs
```bash
terraform destroy -auto-approve 2>&1 | tee destroy-$(date +%Y%m%d-%H%M%S).log
```

## Troubleshooting

### Namespace Stuck in "Terminating"

**Cause**: Finalizers blocking deletion

**Solution**:
```bash
# Check what's blocking
kubectl get namespace <namespace> -o yaml | grep finalizers -A 5

# Remove finalizers
kubectl patch namespace <namespace> -p '{"metadata":{"finalizers":[]}}' --type=merge
```

### Destroy Hangs on Namespace Deletion

**Cause**: Resources with finalizers not being deleted

**Solution**:
```bash
# Force delete all resources in namespace
kubectl delete all --all -n <namespace> --force --grace-period=0

# Or use cleanup script
./scripts/cleanup-namespaces.sh
```

### "Service XXX not found" During Destroy

**Cause**: Service already deleted (normal)

**Result**: Warning message, but destroy continues

**Action**: None required (expected behavior)

### GCP API Rate Limiting

**Symptom**: Destroy slows down or hangs

**Cause**: Too many GCP API calls

**Solution**:
```bash
# Increase timeout
export TF_VAR_namespace_delete_timeout="300s"
terraform destroy -auto-approve
```

## Summary: What Gets Deleted Automatically

✅ **Fully Automated**:
- All Kubernetes namespaces
- All Kubernetes resources (Deployments, Services, ConfigMaps, Secrets)
- All Helm releases
- All cert-manager CRDs
- All Keycloak resources
- All ArgoCD components

⚠️ **May Require Manual Cleanup**:
- GCP LoadBalancer resources (forwarding rules, target pools)

🔍 **Requires Manual Verification**:
- Keycloak realm deletion (check in UI)
- GCP resource cleanup (run scripts)

## Verification Commands

### Complete Verification
```bash
./scripts/verify-destroy.sh
```

### Quick Check
```bash
# Namespaces
kubectl get ns | grep -E 'argocd|agent|cert-manager|ingress-nginx'

# LoadBalancers
gcloud compute forwarding-rules list --regions=europe-west3 | grep ^a

# Helm
helm list -A | grep -E 'cert-manager|nginx-ingress'

# CRDs
kubectl get crd | grep cert-manager
```
