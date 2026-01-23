# ArgoCD Agent - Known Limitations

**Last Updated**: 2026-01-23  
**ArgoCD Agent Version**: v0.5.3+

This document lists known limitations of the ArgoCD Agent architecture that users should be aware of before deployment.

---

## 🔴 Critical Limitations

### 1. UI Resource Tree View "cache: key is missing"

**Status**: ⚠️ **Expected Behavior** (Not a Bug)

**Description**:  
When accessing application details in the ArgoCD UI tree view, users encounter the error:
```
Unable to load data: error getting cached app managed resources: cache: key is missing
```

**Root Cause**:  
The agent architecture uses a **principal-only hub** where the application-controller does NOT run. The UI resource tree view expects a Redis cache populated by the application-controller, but since the controller runs on spoke clusters only, the cache is never populated on the hub.

**Evidence from Logs**:
```json
{
  "grpc.error":"error getting cached app resource tree: cache: key is missing",
  "grpc.method":"ResourceTree",
  "grpc.service":"application.ApplicationService"
}
```

**Impact**: 🟡 Medium  
- **Affected**: UI detailed tree view, live resource inspection
- **Not Affected**: Application list view, sync status, health status, basic operations

**Workarounds**:
1. **Use List View**: Application list view works perfectly (shows sync/health status)
2. **Use CLI**: `kubectl get app -n <namespace>` for detailed status
3. **Access Spoke Directly**: If needed, access spoke cluster's local ArgoCD UI
4. **Check Resources on Spoke**: `kubectl get pods -n <app-namespace> --context <spoke-context>`

**Tracking**: Upstream ArgoCD Agent issue [#612](https://github.com/argoproj-labs/argocd-agent/issues/612) proposes UI improvements.

**Fix Timeline**: No fix planned - architectural design decision. Future UI enhancements may provide alternative views.

---

### 2. No Direct Pod Terminal Access from Hub UI

**Status**: ⚠️ Architectural Limitation

**Description**:  
Cannot open terminal sessions to pods on spoke clusters from the hub ArgoCD UI.

**Root Cause**:  
Terminal access requires streaming WebSocket connections through the resource-proxy. While technically possible, this feature is **not yet implemented** in ArgoCD Agent v0.5.3.

**Impact**: 🟡 Medium  
Users accustomed to ArgoCD's built-in terminal feature will need to use kubectl directly.

**Workarounds**:
```bash
# Terminal access to spoke cluster pods
kubectl --context <spoke-context> exec -it <pod-name> -n <namespace> -- /bin/sh

# Port forwarding
kubectl --context <spoke-context> port-forward -n <namespace> <pod-name> 8080:8080
```

**Tracking**: Terminal support added in ArgoCD Agent v0.6.0+ (not yet released as of 2026-01-23).

**Fix Timeline**: Planned for future release - see [PR #684](https://github.com/argoproj-labs/argocd-agent/pull/684).

---

### 3. ApplicationSet Limited Support

**Status**: ⚠️ Partially Supported

**Description**:  
ApplicationSets work with limitations in the agent architecture.

**Known Issues**:
- **Git Generator**: ✅ Works
- **List Generator**: ✅ Works  
- **Cluster Generator**: ⚠️ Limited (only sees hub cluster, not spoke clusters)
- **Pull Request Generator**: ⚠️ Limited testing

**Root Cause**:  
ApplicationSet controller runs on hub and doesn't have direct access to spoke cluster APIs for discovery.

**Impact**: 🟡 Medium  
Advanced ApplicationSet patterns may not work as expected.

**Workarounds**:
- Use List Generator with explicit spoke cluster definitions
- Define applications explicitly rather than auto-discovery
- Run ApplicationSet controller on spoke (not recommended for hub-spoke model)

**Tracking**: Ongoing upstream development.

---

## 🟡 Performance Limitations

### 4. Increased API Discovery Latency

**Status**: ⚠️ Expected Behavior

**Description**:  
API discovery and resource queries take longer than standard ArgoCD due to multi-hop communication through the resource-proxy.

**Typical Latencies**:
| Operation | Standard ArgoCD | Agent Architecture | Increase |
|-----------|-----------------|-------------------|----------|
| API Discovery | ~5s | ~15-30s | 3-6x |
| Resource Query | ~1s | ~3-5s | 3-5x |
| Application Sync | ~30s | ~45-90s | 1.5-3x |

**Root Cause**:  
Requests travel: **Application Controller → Resource-Proxy → Agent → Principal → Spoke K8s API** (5 hops).

**Impact**: 🟢 Low  
Noticeable during initial sync, negligible during steady-state.

**Mitigation**:  
The Terraform module **automatically configures extended timeouts**:
- Repository server timeout: 300s (vs default 60s)
- Reconciliation timeout: 600s (vs default 180s)
- Connection status cache: 1h (reduces API load)

See [TIMEOUTS.md](../terraform/TIMEOUTS.md) for details.

---

### 5. Hub Principal Not Yet Highly Available

**Status**: ⚠️ Limited HA Support

**Description**:  
The Principal component does not fully support multi-replica highly available configurations in v0.5.3.

**Current HA Status**:
- ✅ Can run multiple replicas (configured via `principal_replicas = 2+`)
- ✅ Load balancing across replicas works
- ⚠️ No leader election (all replicas process events)
- ⚠️ Potential duplicate event processing
- ⚠️ No automatic failover testing

**Impact**: 🟡 Medium  
Single principal replica failure may cause temporary agent disconnection (30s-2min reconnection time).

**Workarounds**:
```hcl
# Terraform configuration for improved resilience
principal_replicas = 2  # Enables HA mode with anti-affinity

# PodDisruptionBudget automatically created
# Anti-affinity rules spread replicas across nodes
```

**Monitoring**:
```bash
# Check principal health
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-agent-principal

# Verify agent connections survive principal restart
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-agent-agent --tail=50
```

**Tracking**: Full HA support planned for future ArgoCD Agent releases.

---

## 🟢 Minor Limitations

### 6. Pattern 2 Multi-Namespace Not Implemented

**Status**: ⚠️ Not Implemented

**Description**:  
The ArgoCD Agent architecture supports two patterns:
- **Pattern 1** (Single Namespace): ✅ Fully implemented and supported
- **Pattern 2** (Multi-Namespace): ❌ Not implemented in this terraform module

**What is Pattern 2?**  
Allows a single agent to manage applications across multiple namespaces on the spoke cluster.

**Current Limitation**:  
Each agent manages applications in the `argocd` namespace only on its spoke cluster.

**Impact**: 🟢 Low  
Most use cases work fine with Pattern 1. Multi-namespace is an advanced feature.

**Workaround**:  
Deploy multiple agents to the same spoke cluster (one per namespace) if multi-namespace isolation is required.

**Tracking**: Pattern 2 support may be added in future terraform module versions.

---

### 7. Spoke Cluster Behind NAT Requirements

**Status**: ⚠️ Outbound Connectivity Required

**Description**:  
Spoke clusters must have **outbound connectivity** to the hub principal (agent initiates connection).

**Network Requirements**:
- Spoke → Hub on port 443 (or 8443): **REQUIRED**
- Hub → Spoke: **NOT REQUIRED** (agent architecture advantage)

**Firewall Rules**:
```bash
# Spoke clusters need outbound HTTPS to principal
ALLOW spoke_network → principal_ip:443 (TCP)

# Hub does NOT need inbound from spokes
```

**Impact**: 🟢 Low  
This is the fundamental agent architecture design (pull-based vs push-based).

**Limitation**:  
Completely air-gapped spoke clusters with zero outbound connectivity cannot use the agent architecture. Consider:
- VPN/bastion tunnels from spoke to hub
- Autonomous mode (not covered by this terraform module)

---

### 8. Resource Proxy Requires Enhanced RBAC

**Status**: ⚠️ Configuration Required

**Description**:  
Default agent installation has **minimal RBAC** (access to ArgoCD resources only). To enable full resource proxy functionality (viewing live resources in UI), agents need enhanced permissions.

**Default Agent Permissions** (Insufficient for Resource Proxy):
```yaml
# Only ArgoCD resources
- apiGroups: ["argoproj.io"]
  resources: ["applications", "appprojects"]
  verbs: ["get", "list", "watch", "update", "patch"]
```

**Required for Resource Proxy** (Must be manually configured):
```yaml
# Application workload resources
- apiGroups: ["", "apps", "networking.k8s.io"]
  resources: ["pods", "services", "deployments", "ingresses", ...]
  verbs: ["get", "list", "watch"]
```

**Impact**: 🟡 Medium  
Without enhanced RBAC, live resource viewing in UI will show permission errors.

**Mitigation**:  
See upstream [Live Resources Documentation](https://argocd-agent.readthedocs.io/latest/user-guide/live-resources/#rbac-requirements) for:
- Common application resource ClusterRole examples
- Application-specific resource permissions
- Security considerations

**Not Automated**:  
Terraform module does NOT automatically apply enhanced RBAC (security best practice - only grant needed permissions).

---

## Comparison with Standard ArgoCD

| Feature | Standard ArgoCD | ArgoCD Agent | Notes |
|---------|-----------------|--------------|-------|
| UI Tree View | ✅ Full | ⚠️ Limited | Cache key missing error |
| Terminal Access | ✅ Yes | ❌ No | Planned for future |
| ApplicationSets | ✅ Full | ⚠️ Partial | Cluster generator limited |
| API Latency | ✅ Low | ⚠️ Higher | 3-6x slower API discovery |
| HA Support | ✅ Full | ⚠️ Limited | Principal HA improving |
| Cluster Discovery | ✅ Yes | ❌ No | Must manually configure |
| Multi-Namespace | ✅ Yes | ⚠️ Pattern 1 Only | Pattern 2 not implemented |
| Outbound Connectivity | ❌ Needed | ✅ Spoke Only | Architecture advantage |
| Resource Proxy | N/A | ⚠️ Needs RBAC | Extra configuration |

---

## When to Use ArgoCD Agent vs Standard ArgoCD

### ✅ Use ArgoCD Agent When:

- Managing clusters across different networks/VPCs
- Spokes are behind NAT/firewall
- Centralized GitOps control plane required
- Air-gapped spokes with VPN outbound
- Scaling to dozens/hundreds of clusters
- Local repo servers needed for security/compliance

### ❌ Consider Standard ArgoCD When:

- All clusters in same VPC with full mesh connectivity
- Need full UI feature parity (terminal, tree view)
- Managing < 5 clusters
- Low latency critical (trading, real-time)
- ApplicationSet cluster discovery essential
- Prefer operational simplicity over architectural flexibility

---

## Reporting New Limitations

If you discover a limitation not listed here:

1. **Verify it's not a known upstream issue**: Check [ArgoCD Agent GitHub Issues](https://github.com/argoproj-labs/argocd-agent/issues)
2. **Check ArgoCD Agent version**: Some limitations fixed in newer versions
3. **Document workaround**: If you find a workaround, share it!
4. **Update this document**: Submit PR with details

---

## Future Improvements

The ArgoCD Agent project is actively developed. Expected improvements:

**Short Term (Next 3 months)**:
- ✅ Web terminal support (merged, pending release)
- Improved ApplicationSet support
- Better HA testing and documentation

**Medium Term (Next 6 months)**:
- Alternative UI views for resource trees
- OpenTelemetry distributed tracing
- SPIFFE authentication support

**Long Term (Next 12 months)**:
- Full multi-tenancy support
- Advanced RBAC features
- Alternative storage backends for scale

---

**Last Reviewed**: 2026-01-23  
**Next Review**: 2026-04-23  
**Maintainer**: Update after each ArgoCD Agent version upgrade

---

**See Also**:
- [Architecture Documentation](../../docs/argocd-agent-architecture.md)
- [Troubleshooting Guide](../../docs/argocd-agent-troubleshooting.md)
- [Upstream ArgoCD Agent Docs](https://argocd-agent.readthedocs.io/)
