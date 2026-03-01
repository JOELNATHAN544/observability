# ArgoCD Agent GitHub Actions Workflow Guide

Complete guide for using the GitHub Actions workflows to deploy ArgoCD Agent in hub-spoke architecture with Netbird connectivity.

> [!IMPORTANT]
> **Prerequisites**: Complete [Netbird Setup Guide](netbird-setup-guide.md) before using these workflows. Spoke clusters must already be in the Netbird network.

## Overview

Two workflows automate the deployment:

1. **`deploy-argocd-hub-gke.yaml`** - Deploy ArgoCD hub cluster to GKE
2. **`deploy-argocd-spokes-netbird.yaml`** - Deploy ArgoCD agents to local spoke clusters via Netbird

---

## Prerequisites Checklist

Before running workflows, ensure:

- [ ] Netbird account created
- [ ] Spoke clusters installed Netbird and registered (persistent peers)
- [ ] GitHub runners setup key created (ephemeral)
- [ ] ACLs configured (`github-runners` → `spoke-clusters`, TCP port 6443)
- [ ] GKE cluster exists for hub deployment
- [ ] All GitHub Secrets configured (see [Netbird Setup Guide](netbird-setup-guide.md#6-github-secrets-configuration))

---

## Deployment Workflow

### Step 1: Deploy Hub Cluster to GKE

The hub cluster runs the ArgoCD control plane and Agent Principal.

#### Trigger Workflow

1. Navigate to **GitHub repository → Actions**
2. Select workflow: **Deploy ArgoCD Hub (GKE)**
3. Click **"Run workflow"**
4. Configure inputs:
   - **Branch**: `main`
   - **Terraform Action**: `plan` *(first run to preview changes)*
   - **Adopt existing resources**: `false` *(set `true` if importing existing ArgoCD)*
5. Click **"Run workflow"**

#### Review Plan

1. Wait for workflow completion (~2-3 minutes)
2. Click on the workflow run
3. Open **"Terraform Plan"** job
4. Review the **"Terraform Plan"** step output
5. Check plan artifacts:
   - Download `tfplan-argocd-hub-gke` artifact
   - Review `plan.txt` for human-readable changes

#### Apply Changes

1. Return to **Actions → Deploy ArgoCD Hub (GKE)**
2. Click **"Run workflow"** again
3. Configure inputs:
   - **Terraform Action**: `apply` *(executes the plan)*
   - **Adopt existing resources**: *(same as plan)*
4. Click **"Run workflow"**
5. **Approval**: If environment protection is enabled, approve the deployment
6. Wait for completion (~5-10 minutes)

#### Extract Outputs

After successful deployment:

1. Open the workflow run
2. Go to **"Terraform Apply & Verify"** job
3. Scroll to **"Verify ArgoCD Hub deployment"** step
4. Find the deployment summary with:
   - **Principal Address**: External IP or hostname
   - **Principal Port**: Usually `443`
   - **ArgoCD UI URL**: For accessing the dashboard

**Example output**:
```
Deployment Summary:
{
  "argocd_url": "https://argocd.example.com",
  "principal_address": "34.123.45.67",
  "principal_port": 443,
  ...
}
```

5. **Download Terraform outputs**:
   - Scroll to bottom of workflow run
   - Download artifact: `terraform-outputs-argocd-hub-gke`
   - Open `terraform-outputs.json`

#### Extract Outputs

After successful deployment, you can verify the deployment details in the workflow output or by downloading the artifact `terraform-outputs-argocd-hub-gke`.

**Example output**:
```
Deployment Summary:
{
  "argocd_url": "https://argocd.example.com",
  "principal_address": "34.123.45.67",
  "principal_port": 443,
  ...
}
```

> [!NOTE]
> The **Deploy Spokes** workflow will automatically discover the Hub Principal address using the Hub Cluster URL/credentials, so you do **not** need to manually create a `HUB_PRINCIPAL_ADDRESS` secret.


---



### Step 3: Deploy Spoke Clusters via Netbird

Deploy ArgoCD agents to local Kubernetes clusters in **Agent-Managed** mode.

#### Trigger Workflow

1. Navigate to **GitHub repository → Actions**
2. Select workflow: **Deploy ArgoCD Spokes (Netbird)**
3. Click **"Run workflow"**
4. Configure inputs:
   - **Branch**: `main`
   - **Terraform Action**: `plan`
   - **Adopt existing resources**: `false`
5. Click **"Run workflow"**

#### Monitor Netbird Connection

1. Open the workflow run
2. Check **"Connect to Netbird"** step to verify VPN mesh connection.
3. Check **"Verify Netbird connection"** step to confirm pings to spoke IPs.

#### Review & Apply

1. Review the **"Terraform Plan"** output.
2. Run workflow again with **Terraform Action**: `apply`.
3. Wait for:
   - Namespace creation (`agent-N`)
   - Agent deployment & connectivity
   - Certificate exchange (Hub <-> Spoke)

#### Verify Agent Connectivity

Check the **"Verify ArgoCD Spoke deployment"** step output:

```
═══════════════════════════════════════════════════════════
Verifying spoke-2...
═══════════════════════════════════════════════════════════
1. Checking namespace...
    Namespace exists
2. Checking ArgoCD pods...
    All pods ready
3. Checking agent connection...
    Agent connected to principal
4. Checking certificates...
    Client certificate exists
    CA certificate exists

All spoke clusters deployed and connected successfully!
```

---

## Using the Import Mechanism

### When to Use

Use `adopt_existing_resources=true` when:
- You have manually deployed ArgoCD already
- Previous Terraform state was lost
- You want to bring existing resources under Terraform management

### Hub Cluster Import

1. Run workflow with **Adopt existing resources**: `true`
2. Workflow will import:
   - ArgoCD namespace
   - Helm releases
   - Visible resources

3. Resources NOT imported (handled automatically):
   - `null_resource` (PKI operations, configurations)
   - These re-run idempotently

**Example import output**:
```
════════════════════════════════════════════════════════════════
Checking for existing ArgoCD resources to import...
════════════════════════════════════════════════════════════════
Found existing argocd namespace
Importing into Terraform state...
Successfully imported kubernetes_namespace.hub_argocd
Found existing ArgoCD Helm release
════════════════════════════════════════════════════════════════
Import check complete! Proceeding with Terraform operations...
════════════════════════════════════════════════════════════════
```

### Spoke Cluster Import

Similar process for spoke clusters:
- Set **Adopt existing resources**: `true`
- Workflow checks each spoke cluster
- Imports namespaces and visible resources
- Agent resources handled idempotently

---

## Workflow Secrets Reference

### Complete Secrets List

#### Netbird
| Secret | Required | Example | Description |
|--------|----------|---------|-------------|
| `NETBIRD_SETUP_KEY_RUNNERS` | Yes | `nb_...` | Ephemeral key for runners |

#### GCP / Hub Cluster
| Secret | Required | Example | Description |
|--------|----------|---------|-------------|
| `GCP_SA_KEY` | Yes | `{"type": "service_account"...}` | Service account JSON |
| `GCP_PROJECT_ID` | Yes | `my-project` | GCP project ID |
| `HUB_CLUSTER_NAME` | Yes | `argocd-hub` | GKE cluster name |
| `HUB_CLUSTER_LOCATION` | Yes | `us-central1` | GKE region |
| `TF_STATE_BUCKET` | Yes | `my-tf-state` | GCS bucket |
| `ARGOCD_HOST` | If using Ingress | `argocd.example.com` | UI hostname |
| `LETSENCRYPT_EMAIL` | If cert-manager | `admin@example.com` | Cert notifications |
| `KEYCLOAK_URL` | If SSO | `https://keycloak.example.com` | Keycloak URL |

#### Spoke Clusters
| Secret | Required | Example | Description |
|--------|----------|---------|-------------|
| `SPOKE_CLUSTERS` | Yes | `spoke-1,spoke-2,spoke-3` | Comma-separated list |

#### Per-Spoke Secrets (repeat for each)
| Secret | Required | Example | Description |
|--------|----------|---------|-------------|
| `SPOKE_1_NETBIRD_IP` | Yes | `100.64.1.10` | Netbird IP |
| `SPOKE_1_CA_CERT` | Yes | `LS0tLS1...` | K8s CA (base64) |
| `SPOKE_1_CLIENT_CERT` | Yes | `LS0tLS1...` | Client cert (base64) |
| `SPOKE_1_CLIENT_KEY` | Yes | `LS0tLS1...` | Client key (base64) |

### How to Generate Secret Values

See [Netbird Setup Guide - Section 5](netbird-setup-guide.md#5-extracting-spoke-cluster-netbird-ips) for detailed instructions on extracting Netbird IPs and Kubernetes credentials.

---

## Troubleshooting Workflows

### Hub Deployment Failures

#### Problem: Terraform plan fails with authentication error

**Cause**: GCP credentials invalid or insufficient permissions

**Solution**:
```bash
# Verify service account has required roles:
# - Kubernetes Engine Admin
# - Compute Viewer (for cluster info)
# - Storage Admin (for state bucket)

# Test credentials locally
gcloud auth activate-service-account --key-file=<SA_KEY_FILE>
gcloud container clusters list --project=<PROJECT_ID>
```

#### Problem: Principal LoadBalancer IP not allocated

**Cause**: GKE cluster quota or regional limits

**Solution**:
1. Check GCP quotas for external IPs
2. Consider using Ingress instead:
   - Set GitHub Variable: `PRINCIPAL_EXPOSE_METHOD=ingress`
   - Requires cert-manager and nginx-ingress

#### Problem: Helm release already exists

**Cause**: ArgoCD previously installed

**Solution**:
- Re-run workflow with **Adopt existing resources**: `true`
- Or manually delete: `helm uninstall argocd -n argocd`

### Spoke Deployment Failures

#### Problem: Cannot connect to Netbird

**Cause**: Invalid setup key or Netbird service down

**Solution**:
1. Verify `NETBIRD_SETUP_KEY_RUNNERS` secret is valid
2. Check setup key expiry in Netbird dashboard
3. Create new key if expired
4. Verify Netbird management service status

#### Problem: Cannot reach spoke cluster via Netbird

**Cause**: Spoke not in Netbird or ACL blocking

**Solution**:
1. Check Netbird dashboard → Peers
2. Verify spoke cluster appears with "Connected" status
3. Check ACL rules allow `github-runners` → `spoke-clusters`
4. Test manually from Netbird peer:
   ```bash
   ping <SPOKE_NETBIRD_IP>
   curl -k https://<SPOKE_NETBIRD_IP>:6443/version
   ```

#### Problem: Agent connection verification fails

**Cause**: Principal address incorrect or network issues

**Solution**:
1. Verify `HUB_PRINCIPAL_ADDRESS` secret matches hub deployment output
2. Check principal service status:
   ```bash
   kubectl get svc argocd-agent-principal -n argocd
   ```
3. Review agent logs on spoke:
   ```bash
   kubectl logs -l app.kubernetes.io/name=argocd-agent-agent -n argocd --tail=100
   ```

#### Problem: Certificate generation fails

**Cause**: PKI not initialized on hub or network issues

**Solution**:
1. Verify hub deployment completed successfully
2. Check PKI CA secret exists on hub:
   ```bash
   kubectl get secret argocd-agent-ca -n argocd
   ```
3. Ensure hub cluster context accessible from workflow

### Common Terraform State Issues

#### Problem: ArgoCD UI inaccessible after re-install (NGINX Ingress)

**Cause**: Stale certificate or missing annotations when using NGINX Inc. Ingress Controller (`nginx.org`)

**Solution**:
1. Ensure the `argocd-server` Ingress has the required annotations:
   ```yaml
   nginx.org/ssl-redirect: "true"
   acme.cert-manager.io/http01-edit-in-place: "true"
   ```
2. If the certificate is stuck or invalid, delete it to force recreation:
   ```bash
   kubectl delete certificate argocd-server-tls -n argocd
   kubectl delete secret argocd-server-tls -n argocd
   ```
3. Re-run the **Deploy ArgoCD Hub** workflow (Terraform will recreate the certificate).

#### Problem: State lock error

**Cause**: Previous run didn't complete cleanly

**Solution**:
```bash
# Manually release lock (use with caution!)
# Download state from GCS
gsutil cp gs://<TF_STATE_BUCKET>/terraform/argocd-hub/default.tflock /tmp/

# Delete lock file
gsutil rm gs://<TF_STATE_BUCKET>/terraform/argocd-hub/default.tflock

# Or wait ~10 minutes for auto-release
```

#### Problem: Resource already exists in state

**Cause**: Running import when resources already managed

**Solution**:
- Run without **Adopt existing resources**
- Or manually remove from state:
  ```bash
  terraform state rm <RESOURCE_ADDRESS>
  ```

---

## Manual Verification

After workflows complete, verify end-to-end functionality:

### 1. Access ArgoCD UI

```bash
# Get UI URL from hub deployment outputs
# Or if using Ingress:
open https://argocd.example.com

# Login with admin credentials
# Default: admin / <auto-generated password>

# Get password:
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

### 2. Verify Spoke Clusters Registered

1. Navigate to **Settings → Clusters**
2. Verify spoke clusters appear:
   - `spoke-1` (or your configured spoke name)
   - `spoke-2`
3. Check status: **Connected** (green)

### 3. Deploy Test Application (Agent-Managed Pattern)

In the verified **Agent-Managed** architecture, you create the Application on the Hub, but the destination server is `https://kubernetes.default.svc`. The Agent on the spoke cluster pulls this configuration and deploys it locally.

**Manifest Example (`guestbook-helm.yaml`):**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: guestbook-helm
  namespace: agent-2  # CRITICAL: Must match the Agent's namespace on the Hub (e.g., 'agent-2')
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj/argocd-example-apps.git
    targetRevision: HEAD
    path: helm-guestbook
  destination:
    # URL for the Agent's LOCAL cluster (the spoke)
    # The Agent interprets this as "deploy to the cluster I am running in"
    server: https://kubernetes.default.svc
    namespace: guestbook-helm
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

**Steps:**
1. Apply the manifest to the **Hub Cluster**:
   ```bash
   kubectl apply -f guestbook-helm.yaml
   ```
2. Wait for the Agent (on Spoke) to pull the config (~30s).
3. Check status on Hub:
   ```bash
   kubectl get application guestbook-helm -n agent-2
   # Should show: SYNC STATUS: Synced, HEALTH STATUS: Healthy
   ```

### 4. Verify on Spoke Cluster

You can verify the pods are actually running on the spoke cluster:

```bash
# Using Netbird connection (spoke-2 example context)
export KUBECONFIG=$HOME/.kube/config:$HOME/.kube/spoke-2.yaml

kubectl get pods -n guestbook-helm --context spoke-2
# Expected: guestbook pods running
```

---

## Frequently Asked Questions (FAQ)

**Q: When should I use `plan` vs `apply` in workflows?**

**A:** Always run `plan` first to preview changes. Review the plan output and artifacts, then run `apply` only after confirming changes are correct. This two-step process prevents accidental infrastructure changes.

---

**Q: How do I verify spoke clusters are successfully connected?**

**A:** Check the workflow logs for the "Verify ArgoCD Spoke deployment" step. Look for all green checkmarks:
- Namespace exists
- All pods ready
- Agent connected to principal
- Client certificate exists

Or verify manually: `kubectl --context=spoke-2 logs -n argocd -l app.kubernetes.io/name=argocd-agent --tail=20 | grep "connected"`

---

**Q: What happens if a workflow fails midway through `apply`?**

**A:** Terraform tracks state remotely in GCS. Failed applies are safe - simply re-run the workflow. Terraform will detect the current state and continue where it left off. Check for state locks (auto-released after 10 minutes) if you encounter issues.

---

**Q: How long do workflow runs take?**

**A:**
- **Hub Plan**: 2-3 minutes
- **Hub Apply**: 5-10 minutes
- **Spoke Plan** (per cluster): 1-2 minutes
- **Spoke Apply** (per cluster): 3-5 minutes

For 3 spoke clusters, expect ~20-25 minutes total for full deployment.

---

**Q: Workflow shows "Netbird peer sync timeout" - is this a problem?**

**A:** The GitHub runner couldn't discover Netbird peers within 60 seconds. The workflow continues anyway with a warning. Common causes:
- Netbird management server is slow/overloaded
- Network connectivity issues
- Spoke clusters not connected to Netbird yet

Verify spoke connectivity manually if the deployment fails. See [Netbird Setup Guide](netbird-setup-guide.md#7-testing-netbird-connectivity) for testing steps.

---

**Q: Can I deploy to multiple spoke clusters in one workflow run?**

**A:** Yes! Add all spoke clusters to the `SPOKE_CLUSTERS` secret (comma-separated). The workflow deploys them sequentially. Example: `spoke-1,spoke-2,spoke-3`

---

**Q: What does `adopt_existing_resources=true` do?**

**A:** It imports existing ArgoCD resources into Terraform state without recreating them. Use this when migrating from manual deployment, recovering from lost Terraform state, or taking over management of existing installations.

---

**Q: Do I need to redeploy spokes when I upgrade the hub?**

**A:** Not immediately, but recommended. ArgoCD Agent maintains backward compatibility for 1-2 minor versions. Upgrade spokes within a week of hub upgrades to avoid compatibility issues.

---

## Maintenance Guide for GitHub Actions

### Daily Monitoring (5 minutes)

**Check Workflow Health**
- [ ] Review failed workflow runs in Actions tab
- [ ] Check for stuck workflow runs (> 1 hour)
- [ ] Verify Netbird connection logs for errors

**Quick Commands**:
```bash
# Check last 5 workflow runs via GitHub CLI
gh run list --workflow=deploy-argocd-hub-gke.yaml --limit 5

# Check for rate limit issues
gh api rate_limit
```

---

### Weekly Tasks (15 minutes)

**Monday: Secret Hygiene**
- [ ] Review GitHub Secrets expiration warnings
- [ ] Verify Netbird setup key hasn't expired
- [ ] Check GCP service account key age (rotate if > 90 days)

**Wednesday: Cost Review**
- [ ] Review GitHub Actions minutes usage
- [ ] Check GCS storage costs for Terraform state
- [ ] Verify LoadBalancer costs for principal

**Friday: Workflow Updates**
- [ ] Check for workflow deprecation warnings
- [ ] Review Actions marketplace for updates
- [ ] Test workflows in dev/staging environment

---

### Monthly Tasks (1-2 hours)

**Security Audit** (First Monday)
- [ ] Rotate `NETBIRD_SETUP_KEY_RUNNERS`
- [ ] Review OIDC configuration for GCP (if using)
- [ ] Audit GitHub repository access logs
- [ ] Check for leaked secrets in workflow logs

**Workflow Optimization** (Second Week)
- [ ] Analyze workflow run times for bottlenecks
- [ ] Review caching strategies for dependencies
- [ ] Update Terraform/kubectl versions in workflows
- [ ] Test disaster recovery procedure

**Documentation Update** (Third Week)
- [ ] Update README with workflow changes
- [ ] Review and update troubleshooting guides
- [ ] Document any custom workflow modifications
- [ ] Update team runbooks

---

### Quarterly Tasks (Half day)

**Major Version Upgrades**
- [ ] Plan ArgoCD version upgrades
- [ ] Test workflows against new Terraform versions
- [ ] Review Netbird API changes
- [ ] Update GitHub Actions dependencies

**Disaster Recovery Drill**
- [ ] Test hub cluster recovery from backup
- [ ] Verify Terraform state recovery from GCS
- [ ] Practice re-running workflows from scratch
- [ ] Document lessons learned

---

### Annual Tasks (Full day)

**Comprehensive Review**
- [ ] Evaluate workflow architecture (monolithic vs modular)
- [ ] Consider self-hosted runners for cost savings
- [ ] Review GitHub Advanced Security findings
- [ ] Assess ROI of automation vs manual deployment

---

## Cost Estimation & Optimization

### GitHub Actions Minutes

**Free Tier**: 2,000 minutes/month (public repos unlimited)

**Estimated Usage**:
| Scenario | Monthly Runs | Minutes Used | Cost |
|----------|--------------|--------------|------|
| Weekly deployments (hub + 3 spokes) | 4 | ~100 min | Free |
| Daily deployments | 30 | ~750 min | Free |
| CI/CD on every commit | 150+ | ~3,750 min | ~$8/month |

**Optimization Tips**:
1. Use `workflow_dispatch` instead of `push` triggers
2. Implement path filters to avoid unnecessary runs
3. Cache Terraform providers and kubectl binaries
4. Consider self-hosted runners for high-frequency deployments

---

### GCP Costs

**Hub Cluster** (per month):
- GKE Control Plane: $72 (regional) / $0 (autopilot)
- LoadBalancer (Principal): ~$18
- Compute Nodes: ~$50-200 (depending on size)
- **Total**: ~$140-290/month

**Spoke Clusters**: 
- No GCP costs if running on-premises
- Netbird egress: Negligible (~$0.10/GB)

**Terraform State Storage**:
- GCS bucket: ~$0.02/GB/month
- Minimal cost (state files < 10 MB typically)

**Cost Reduction Strategies**:
1. Use GKE Autopilot for hub cluster
2. Use Ingress instead of LoadBalancer for principal
3. Implement cluster auto-scaling
4. Use preemptible nodes for non-production

---

## Security Best Practices

### GitHub Secrets Management

**Critical Secrets Rotation Schedule**:
| Secret | Rotation Frequency | Impact |
|--------|-------------------|--------|
| `GCP_SA_KEY` | 90 days | High - Redeploy workflows |
| `NETBIRD_SETUP_KEY_RUNNERS` | 90 days | Low - Update secret only |
| `SPOKE_N_CLIENT_KEY` | Annually | Medium - Spoke re-auth |
| `DEFAULT_ADMIN_PASSWORD` | 90 days | Low - User management |

**Protection Measures**:
1. Enable **Required Reviewers** for production environment
2. Use **Environment Secrets** instead of repository secrets
3. Enable **GitHub Advanced Security** secret scanning
4. Implement **OIDC** instead of static GCP service account keys

**Example: OIDC Configuration for GCP** (Recommended)
```yaml
- name: Authenticate to Google Cloud
  uses: google-github-actions/auth@v1
  with:
    workload_identity_provider: 'projects/123456789/locations/global/workloadIdentityPools/github-pool/providers/github-provider'
    service_account: 'github-actions@project-id.iam.gserviceaccount.com'
```

---

### Network Security

**Netbird Hardening**:
1. **Enable MFA** for Netbird dashboard access
2. **Restrict ACLs** to minimum required ports (6443 only)
3. **Monitor peer activity** in Netbird dashboard
4. **Set setup key expiry** to 90 days maximum
5. **Enable audit logging** for compliance

**GitHub Actions Runner Security**:
1. Use **ephemeral Netbird keys** (auto-cleanup after 10 minutes)
2. Never use persistent setup keys for runners
3. Implement **IP allowlisting** if using self-hosted runners
4. Enable **audit logs** for workflow runs

---

### Compliance Considerations

**Data Residency**:
- Terraform state stored in GCS (specify region)
- Workflow logs stored in GitHub (US/EU regions)
- Netbird metadata location (check your deployment)

**Audit Trail**:
- All workflow runs logged in GitHub Actions
- Terraform state changes tracked in GCS versioning
- Netbird connection logs available via dashboard

**SOC2/ISO27001 Requirements**:
- Enable GCS object versioning for state files
- Implement GitHub organization security policies
- Document workflow approval processes
- Maintain runbooks for incident response

---

## Workflow Execution Flow

### Hub Deployment Flow

```
┌─────────────────────────────────────────────────────────┐
│ 1. Trigger Workflow (Manual or Push)                    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 2. Checkout Code & Setup Tools                          │
│    - Terraform v1.9.0                                    │
│    - kubectl v1.28.0                                     │
│    - gcloud CLI                                          │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 3. Authenticate to GCP                                   │
│    - Service Account or OIDC                             │
│    - Configure kubectl context                           │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 4. Generate Configuration Files                          │
│    - backend.tf (GCS state)                              │
│    - terraform.tfvars                                    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 5. Terraform Init & Validate                             │
│    - Download providers                                  │
│    - Initialize backend                                  │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 6. Terraform Plan                                        │
│    - Generate execution plan                             │
│    - Upload artifacts                                    │
└─────────────────────────────────────────────────────────┘
                          ↓
              ┌───────────────────────┐
              │  Manual Review         │
              │  (if action=plan)      │
              └───────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 7. Terraform Apply (if action=apply)                     │
│    - Create namespace                                    │
│    - Deploy cert-manager (if enabled)                    │
│    - Deploy nginx-ingress (if enabled)                   │
│    - Install ArgoCD via Helm                             │
│    - Configure Principal                                 │
│    - Setup Keycloak SSO (if enabled)                     │
│    - Wait for LoadBalancer IP                            │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 8. Verification                                          │
│    - Check pod status                                    │
│    - Verify principal connectivity                       │
│    - Test ArgoCD UI access                               │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 9. Export Outputs                                        │
│    - Upload terraform-outputs.json                       │
│    - Display deployment summary                          │
└─────────────────────────────────────────────────────────┘
```

### Spoke Deployment Flow

```
┌─────────────────────────────────────────────────────────┐
│ 1. Trigger Workflow                                      │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 2. Connect to Netbird                                    │
│    - Install Netbird CLI                                 │
│    - Connect using RUNNERS setup key                     │
│    - Wait for peer sync (60s timeout)                    │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 3. Verify Connectivity                                   │
│    - Ping spoke cluster Netbird IPs                      │
│    - Test port 6443 reachability                         │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 4. Configure kubectl for Spokes                          │
│    - Read secrets (SPOKE_N_NETBIRD_IP, certs)            │
│    - Generate kubeconfig contexts                        │
│    - Verify API server access                            │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 5. Fetch Hub Principal Address                           │
│    - Query hub cluster LoadBalancer service              │
│    - Resolve IP/hostname automatically                   │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 6. Terraform Plan/Apply                                  │
│    - FOR EACH spoke cluster:                             │
│      • Create agent namespace                            │
│      • Generate client certificates                      │
│      • Deploy ArgoCD agent                               │
│      • Configure principal connection                    │
│      • Deploy application controller                     │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 7. Verification (per spoke)                              │
│    - Check namespace exists                              │
│    - Verify pods are ready                               │
│    - Test agent connection to principal                  │
│    - Validate certificates                               │
└─────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────┐
│ 8. Cleanup                                               │
│    - Disconnect from Netbird                             │
│    - (Ephemeral peer auto-removed after 10 min)          │
└─────────────────────────────────────────────────────────┘
```

---

## Next Steps

After successful deployment:

1. **Configure Applications**: Create apps in ArgoCD UI targeting spoke clusters
2. **Set up Git repositories**: Connect your application repositories
3. **Configure RBAC**: Set up user access controls (or integrate with Keycloak)
4. **Monitor Agents**: Check agent logs and connectivity regularly
5. **Backup**: Schedule regular backups of:
   - PKI CA certificates
   - ArgoCD configuration
   - Terraform state (already in GCS)
6. **Review Security**: Implement secrets rotation schedule from guide above
7. **Schedule Maintenance**: Follow the maintenance calendar for optimal health

---

## Additional Resources

### Official Documentation
- [ArgoCD Agent Documentation](https://argocd-agent.readthedocs.io/latest)
- [Netbird Documentation](https://docs.netbird.io/)
- [Terraform Kubernetes Provider](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)

### Internal Guides
- [Operations Guide](argocd-agent-operations.md) - Day-2 operations, scaling, monitoring
- [Troubleshooting Guide](argocd-agent-troubleshooting.md) - Common issues and solutions
- [Configuration Reference](argocd-agent-configuration.md) - All Terraform variables
- [Netbird Setup Guide](netbird-setup-guide.md) - Network infrastructure setup
- [Architecture Guide](argocd-agent-architecture.md) - Hub-spoke design patterns

### Community & Support
- [ArgoCD Slack](https://argoproj.github.io/community/join-slack) - `#argocd-agent` channel
- [Netbird Community](https://netbird.io/community) - Support forum
- [GitHub Issues](https://github.com/argoproj-labs/argocd-agent/issues) - Bug reports and feature requests
