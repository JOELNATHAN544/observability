# ArgoCD Agent - Troubleshooting Guide

This guide documents all known issues and their solutions for the ArgoCD Hub-and-Spoke architecture.

## Quick Diagnostics

### Hub Health Check

```bash
# Set Hub context
export HUB_CTX="your-hub-context"

# 1. Check all pods running
kubectl --context=$HUB_CTX get pods -n argocd

# 2. Principal logs
kubectl --context=$HUB_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent-principal --tail=50

# 3. Redis connectivity
kubectl --context=$HUB_CTX exec -n argocd deployment/argocd-agent-principal -- \
  redis-cli -h argocd-redis ping

# 4. Spoke management namespaces
kubectl --context=$HUB_CTX get ns | grep spoke

# 5. RBAC check
kubectl --context=$HUB_CTX auth can-i list applications.argoproj.io \
  --as=system:serviceaccount:argocd:argocd-agent-principal \
  -n spoke-01-mgmt
```

### Spoke Health Check

```bash
# Set Spoke context
export SPOKE_CTX="your-spoke-context"

# 1. Check all pods running
kubectl --context=$SPOKE_CTX get pods -n argocd

# 2. Agent logs
kubectl --context=$SPOKE_CTX logs -n argocd -l app.kubernetes.io/name=argocd-agent --tail=50

# 3. Agent certificates
kubectl --context=$SPOKE_CTX exec -n argocd deployment/argocd-agent -- \
  ls -la /app/config/tls

# 4. Application controller config
kubectl --context=$SPOKE_CTX get deployment -n argocd argocd-application-controller \
  -o yaml | grep -A5 "ARGOCD_APPLICATION_CONTROLLER_REPO_SERVER"

# 5. RBAC check
kubectl --context=$SPOKE_CTX auth can-i create applications.argoproj.io \
  --as=system:serviceaccount:argocd:argocd-agent \
  -n argocd
```

## Known Issues and Solutions

### Issue 1: Redis NetworkPolicy Blocking Principal

**Symptom**:
- Agent Principal logs show: `Error connecting to Redis`
- Principal pod cannot reach Redis service

**Root Cause**:
NetworkPolicy is missing `argocd-agent-principal` pod selector in allowed pods.

**Solution**:
The Terraform module includes this fix in `hub.tf`:

```yaml
# NetworkPolicy includes Principal
ingress:
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: argocd-agent-principal  # CRITICAL
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: argocd-server
```

**Verification**:
```bash
kubectl --context=$HUB_CTX get networkpolicy -n argocd redis-allow-principal -o yaml
```

---

### Issue 2: JWT Key Format Errors

**Symptom**:
- Principal crashes with: `invalid key format`
- Server won't start

**Root Cause**:
JWT key is not RSA 4096-bit PEM format (e.g., using ECDSA or wrong size).

**Solution**:
The Terraform PKI module generates correct format automatically:

```hcl
resource "tls_private_key" "jwt_key" {
  algorithm = "RSA"
  rsa_bits  = 4096  # MUST be 4096
}
```

**Verification**:
```bash
kubectl --context=$HUB_CTX get secret -n argocd argocd-secret \
  -o jsonpath='{.data.server\.secretkey}' | base64 -d | \
  openssl rsa -text -noout | head -n1
# Should show: Private-Key: (4096 bit)
```

---

### Issue 3: Principal Not Detecting Applications

**Symptom**:
- Applications created on Hub not mirrored to Spoke
- Agent logs show no Applications received

**Root Cause**:
Principal missing RBAC permissions for spoke management namespaces.

**Solution**:
The Terraform module creates proper RBAC in `rbac.tf`:

```yaml
# Role in spoke management namespace
kind: Role
metadata:
  name: argocd-agent-principal
  namespace: spoke-01-mgmt
rules:
- apiGroups: ["argoproj.io"]
  resources: ["applications"]
  verbs: ["get", "list", "watch", "update", "patch"]
```

**Verification**:
```bash
kubectl --context=$HUB_CTX get role -n spoke-01-mgmt argocd-agent-principal
kubectl --context=$HUB_CTX auth can-i watch applications --as=system:serviceaccount:argocd:argocd-agent-principal -n spoke-01-mgmt
```

---

### Issue 4: Application Namespace Confusion

**Symptom**:
- Applications not appearing in expected namespace
- Sync errors about namespace not found

**Root Cause**:
Confusion between Pattern 1 (single namespace) and Pattern 2 (multi-namespace).

**Solution**:
This implementation uses **Pattern 1**:
- Applications created on Hub in: `spoke-01-mgmt` namespace
- Agent configured with: `ARGOCD_AGENT_NAMESPACE=spoke-01-mgmt`
- Applications mirrored to Spoke in: `argocd` namespace

**Verification**:
```bash
# Check Agent configuration
kubectl --context=$SPOKE_CTX get deployment -n argocd argocd-agent \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ARGOCD_AGENT_NAMESPACE")].value}'
# Should output: spoke-01-mgmt
```

---

### Issue 5: Multi-Namespace Agent RBAC

**Symptom** (Pattern 2 only):
- Agent cannot access resources in watched namespaces
- Permission denied errors in Agent logs

**Root Cause**:
Agent Service Account only has Role in single namespace.

**Solution** (for future Pattern 2 implementation):
Create RoleBindings in ALL watched namespaces or use ClusterRole.

```yaml
# ClusterRole for multi-namespace access
kind: ClusterRole
metadata:
  name: argocd-agent
# ... with RoleBindings in each watched namespace
```

**Note**: Current implementation (Pattern 1) doesn't have this issue.

---

### Issue 6: Certificate IP Mismatch

**Symptom**:
- TLS handshake failures
- Agent logs: `x509: certificate is valid for X, not Y`

**Root Cause**:
LoadBalancer IP changed after certificate generation.

**Solution**:
1. **Use DNS names** in certificates (Terraform uses hostnames, not IPs)
2. **Reserve static IP** for LoadBalancer

**For GKE**:
```bash
# Reserve static IP
gcloud compute addresses create argocd-principal-ip --region=us-central1

# Configure Ingress to use reserved IP
annotations:
  kubernetes.io/ingress.global-static-ip-name: "argocd-principal-ip"
```

**Verification**:
```bash
# Check certificate SANs
kubectl --context=$HUB_CTX get ingress -n argocd argocd-agent-principal \
  -o jsonpath='{.spec.tls[0].hosts[0]}'
```

---

### Issue 7: Agent Authentication Confusion

**Symptom**:
- Agent using wrong auth method
- Logs show: `authentication failed`

**Root Cause**:
Both `ARGOCD_AGENT_CREDS` and mTLS configured.

**Solution**:
Set `ARGOCD_AGENT_CREDS=""` (empty string) to enable mTLS mode.

The Terraform module sets this correctly in `spoke.tf`:

```hcl
env {
  name  = "ARGOCD_AGENT_CREDS"
  value = ""  # Empty enables mTLS
}
```

**Verification**:
```bash
kubectl --context=$SPOKE_CTX get deployment -n argocd argocd-agent \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ARGOCD_AGENT_CREDS")].value}'
# Should be empty
```

---

### Issue 8: Application Controller Placement

**Symptom**:
- Confusion about where app controller should run

**Clarification**:
- **Hub**: NO application controller (replicas: 0)
- **Spoke**: YES application controller (replicas: 1+)

This is true for BOTH Pattern 1 and Pattern 2.

**Verification**:
```bash
# Hub should have 0 replicas
kubectl --context=$HUB_CTX get deployment -n argocd argocd-application-controller \
  -o jsonpath='{.spec.replicas}'
# Output: 0

# Spoke should have 1+ replicas
kubectl --context=$SPOKE_CTX get deployment -n argocd argocd-application-controller \
  -o jsonpath='{.spec.replicas}'
# Output: 1 (or higher)
```

---

### Issue 9: Resource-Proxy API Discovery Timeouts

**Symptom**:
- Application sync status shows "Unknown/Unknown" on Hub
- Application controller logs show: `error synchronizing cache state: failed to get api resources: failed to discover server resources, zero resources returned: the server was unable to return a response in the time allotted`
- Errors occur specifically for spoke clusters accessed via resource-proxy
- Principal logs show agents successfully connected and sending cache updates

**Root Cause**:
ArgoCD's default timeout settings (60s for repo server, 180s for reconciliation) are insufficient for the agent-based architecture. The resource-proxy adds latency because it must relay API discovery requests through the agent connection to the spoke cluster, and responses take longer to return through this multi-hop path.

**Solution**:
Increase timeout values in ArgoCD ConfigMaps. The Terraform module automatically configures these in `main.tf`:

1. **Repository Server Timeout** (argocd-cmd-params-cm):
```yaml
data:
  controller.repo.server.timeout.seconds: "300"  # 5 minutes
  server.connection.status.cache.expiration: "1h"  # Cache cluster status longer
```

2. **Reconciliation Timeouts** (argocd-cm):
```yaml
data:
  timeout.reconciliation: "600s"  # 10 minutes
  timeout.hard.reconciliation: "0"  # No hard limit
```

**Manual Application** (if not using Terraform):
```bash
# Update argocd-cmd-params-cm
kubectl patch configmap argocd-cmd-params-cm -n argocd \
  --type='merge' \
  --patch '{"data":{
    "controller.repo.server.timeout.seconds":"300",
    "server.connection.status.cache.expiration":"1h"
  }}'

# Update argocd-cm
kubectl patch configmap argocd-cm -n argocd \
  --type='merge' \
  --patch '{"data":{
    "timeout.reconciliation":"600s",
    "timeout.hard.reconciliation":"0"
  }}'

# Restart components to apply changes
kubectl rollout restart deployment argocd-server -n argocd
kubectl rollout restart statefulset argocd-application-controller -n argocd

# Wait for rollouts to complete
kubectl rollout status deployment/argocd-server -n argocd
kubectl rollout status statefulset/argocd-application-controller -n argocd
```

**Verification**:
```bash
# Check ConfigMaps have timeout settings
kubectl get configmap argocd-cmd-params-cm -n argocd -o yaml | grep timeout
kubectl get configmap argocd-cm -n argocd -o yaml | grep timeout

# Monitor application sync status
kubectl get applications -n <agent-namespace> -w

# Check application controller logs for timeout errors
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

**Troubleshooting**:
If applications still show timeouts after configuration:
1. Verify the ConfigMap changes were applied: `kubectl describe cm argocd-cmd-params-cm -n argocd`
2. Confirm components restarted: `kubectl get pods -n argocd -o wide`
3. Check agent connectivity: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-agent-principal`
4. Test resource-proxy directly from a debug pod:
```bash
kubectl run -it --rm debug --image=curlimages/curl -n argocd -- \
  curl -v http://argocd-agent-resource-proxy.argocd.svc.cluster.local:9090/healthz?agentName=agent-1
```

---

## Common Error Messages

### "Connection refused" from Agent

**Possible Causes**:
1. Hub Principal not running
2. Ingress not configured
3. DNS not resolving
4. Firewall blocking port 8443

**Debug Steps**:
```bash
# 1. Check Principal running
kubectl --context=$HUB_CTX get pods -n argocd -l app.kubernetes.io/name=argocd-agent-principal

# 2. Check Ingress
kubectl --context=$HUB_CTX get ingress -n argocd argocd-agent-principal

# 3. Test DNS from Spoke
kubectl --context=$SPOKE_CTX run -it --rm debug --image=curlimages/curl -- \
  nslookup agent-principal.example.com

# 4. Test connectivity
kubectl --context=$SPOKE_CTX run -it --rm debug --image=curlimages/curl -- \
  curl -v telnet://agent-principal.example.com:8443
```

### "x509: certificate signed by unknown authority"

**Cause**: Spoke Agent doesn't have Hub CA certificate.

**Fix**:
```bash
# Check CA cert exists on Spoke
kubectl --context=$SPOKE_CTX get secret -n argocd argocd-agent-client-cert \
  -o jsonpath='{.data.ca\.crt}' | base64 -d | openssl x509 -text -noout

# Should match Hub CA
kubectl --context=$HUB_CTX get secret -n argocd argocd-agent-ca \
  -o jsonpath='{.data.ca\.crt}'| base64 -d | openssl x509 -text -noout
```

### "Application has invalid spec"

**Cause**: Application destination server incorrect.

**Fix**:
For spoke deployments, use:
```yaml
destination:
  server: https://kubernetes.default.svc  # NOT the spoke cluster URL
  namespace: target-namespace
```

## Terraform-Specific Issues

### "Provider configuration not present"

**Cause**: Missing provider alias or incorrect configuration.

**Fix**:
Ensure both Hub and Spoke providers are configured in `provider.tf` even if only deploying one.

### "Certificate has expired"

**Cause**: Certificate validity period exceeded.

**Fix**:
Rotate certificates using Terraform:
```bash
terraform taint tls_self_signed_cert.hub_ca[0]
terraform taint tls_locally_signed_cert.spoke_client[0]
terraform apply
```

See [PKI Management Guide](argocd-agent-pki-management.md)

## Getting Help

If your issue isn't listed here:

1. **Check logs** on both Hub and Spoke
2. **Verify RBAC** permissions
3. **Test network** connectivity
4. **Review Terraform** state and plan
5. **Consult [ArgoCD Agent documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/agent/)**

## Reporting Issues

When reporting issues, includetest:

- Deployment mode (Hub-only, Spoke-only, or Full)
- ArgoCD version and Helm chart version
- Terraform version
- Relevant logs from Principal and/or Agent
- Terraform plan output (redact sensitive data)
- Network topology (same cluster, different clusters, cloud provider)
