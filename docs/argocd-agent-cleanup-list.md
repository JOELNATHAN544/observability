# Documentation Cleanup List

**Generated**: 2026-01-23  
**Purpose**: Track content to delete, deprecate, or consolidate

---

## Summary

**Total Items**: 5  
**Deletions**: 0  
**Updates Required**: 5  
**Consolidations**: 0  

**Overall Assessment**: Documentation is well-maintained. No deletions needed, only accuracy updates.

---

## 1. Content to Delete

### ❌ **NONE**

All existing documentation serves a purpose and is accurate. No files recommended for deletion.

---

## 2. Content to Update (Accuracy Fixes)

### 2.1 Version References

**Files Affected**:
- `argocd-agent/README.md`
- `docs/argocd-agent-terraform-deployment.md`

**Issue**: References to `v0.5.3` don't clarify if that's minimum or recommended version.

**Fix**:
```markdown
# Before
argocd_version = "v0.5.3"

# After  
argocd_version = "v0.5.3"  # Minimum: v0.5.3 | Tested: v0.5.3
```

**Priority**: 🟢 Low  
**Effort**: 5 minutes  
**Status**: ⏸️ Pending

---

### 2.2 LoadBalancer vs Ingress Defaults

**Files Affected**:
- `argocd-agent/README.md` (line ~69)
- `argocd-agent/terraform/README.md` (line ~134)
- `docs/argocd-agent-terraform-deployment.md` (line ~69-75)

**Issue**: Sometimes shows LoadBalancer, sometimes Ingress as the default without clarification.

**Fix**: Add explicit statement:
```markdown
## Exposure Methods

**Default**: LoadBalancer (simplest setup, requires cloud provider LB support)  
**Alternative**: Ingress (requires cert-manager + ingress-nginx, provides DNS/TLS)

| Method | Pros | Cons | Use When |
|--------|------|------|----------|
| LoadBalancer | Simple, automatic | Costs $, requires cloud LB | Development, small deployments |
| Ingress | DNS/TLS included, cost-effective | Complex setup | Production, custom domains |
```

**Priority**: 🟡 Medium  
**Effort**: 15 minutes  
**Status**: ⏸️ Pending

---

### 2.3 Agent Name Terminology Standardization

**Files Affected**:
- All documentation files (inconsistent use of `spoke-01`, `agent-1`, `spoke-1`)

**Issue**: Terminology inconsistency causes confusion.

**Standardization**:
```markdown
# Preferred Terminology (matches terraform vars)
workload_clusters = {
  "agent-1" = "context-1"  # Use "agent-N"
  "agent-2" = "context-2"
}

# In Documentation
- **Agent Name**: agent-1, agent-2, agent-N (lowercase, hyphenated)
- **Namespace on Hub**: agent-1, agent-2 (matches agent name)
- **Namespace on Spoke**: argocd (always)

# Avoid
- ❌ spoke-01 (old pattern)
- ❌ spoke-1 (inconsistent)
- ❌ agent_1 (underscores)
```

**Search and Replace**:
```bash
# Find inconsistent usage
grep -rn "spoke-[0-9]" docs/ argocd-agent/
grep -rn "spoke_[0-9]" docs/ argocd-agent/

# Replace with agent-N pattern
```

**Priority**: 🟡 Medium  
**Effort**: 30 minutes  
**Status**: ⏸️ Pending

---

### 2.4 Pattern 2 Multi-Namespace References

**Files Affected**:
- `docs/argocd-agent-architecture.md` (mentions Pattern 2)
- `docs/argocd-agent-troubleshooting.md` (Issue 5 references Pattern 2)

**Issue**: Pattern 2 (multi-namespace per agent) is **not implemented** but referenced in docs as if it exists.

**Fix Options**:

**Option A: Remove Pattern 2 references entirely**
```markdown
# Delete sections like:
### Issue 5: Multi-Namespace Agent RBAC

**Symptom** (Pattern 2 only):  # DELETE THIS ENTIRE SECTION
```

**Option B: Mark Pattern 2 as future/experimental**
```markdown
## Pattern 2: Multi-Namespace (Not Implemented)

**Status**: 🚧 Not implemented in current terraform modules  
**Future**: May be added in future versions

Current implementation uses **Pattern 1 only** (single namespace per agent).
```

**Recommendation**: **Option B** - Keep for reference but clearly mark as not implemented.

**Priority**: 🟡 Medium  
**Effort**: 15 minutes  
**Status**: ⏸️ Pending

---

### 2.5 Application Controller Placement

**Files Affected**:
- `docs/argocd-agent-architecture.md` (diagrams at line ~10-63)

**Issue**: Need to verify all diagrams correctly show app-controller **only** on spoke, **never** on hub.

**Verification Checklist**:
- [x] Main architecture diagram (line 10-63) - ✅ CORRECT (no app-controller in hub)
- [ ] Component breakdown table (line 65-76) - VERIFY
- [ ] Network architecture diagram (line 90-120) - VERIFY

**Fix**: Audit all diagrams, ensure app-controller absent from hub components.

**Priority**: 🟡 Medium  
**Effort**: 20 minutes  
**Status**: ⏸️ Pending

---

## 3. Content to Consolidate

### ❌ **NONE**

No consolidation needed. Documentation is well-factored:
- RBAC.md and TIMEOUTS.md could be merged into one file but they're clearer separated
- Destroy docs (DESTROY-ORDER.md + DESTROY-CLEANUP.md) serve different purposes
- Architecture vs deployment vs troubleshooting are correctly separated

---

## 4. Content to Reorganize

### ❌ **NONE**

Current organization is logical and follows project conventions. No reorganization needed.

**Existing Structure (Keep)**:
```
argocd-agent/
├── README.md                  # Overview
├── docs/                      # Operational docs
└── terraform/
    ├── README.md              # Terraform overview
    ├── RBAC.md                # Reference docs
    └── TIMEOUTS.md            # Reference docs

docs/  (global)
├── argocd-agent-architecture.md       # Concepts
├── argocd-agent-terraform-deployment.md   # How-to
├── argocd-agent-troubleshooting.md    # Issue resolution
└── argocd-agent-pki-management.md     # Reference
```

---

## 5. Deprecated Content to Mark

### ❌ **NONE**

No deprecated content found. All documentation reflects current implementation.

---

## 6. Redundant Content to Remove

### ❌ **NONE**

No redundant content found. Each document serves a unique purpose:
- No duplicate information across files
- Cross-references are appropriate and helpful
- Examples are context-specific, not copy-pasted

---

## 7. Outdated Content to Update

### ❌ **NONE** (Beyond accuracy fixes in Section 2)

All content reflects current terraform implementation (Sessions 5-7 updates applied).

---

## 8. Implementation Checklist

**Quick Wins (< 1 hour total)**:
- [ ] Standardize version references (5 min)
- [ ] Clarify LoadBalancer vs Ingress defaults (15 min)
- [ ] Mark Pattern 2 as not implemented (15 min)
- [ ] Verify app-controller placement in diagrams (20 min)

**Medium Effort (30-60 min)**:
- [ ] Standardize agent naming terminology (30 min)

**Total Effort**: ~1.5 hours to clean up all accuracy issues

---

## 9. Notes

### Why No Deletions?

Documentation quality is high:
1. **DESTROY-ORDER.md**: Extremely detailed, helps users understand terraform destroy
2. **DESTROY-CLEANUP.md**: Practical cleanup procedures for edge cases
3. **DO_NOT_USE_HERE.md**: Prevents common mistake (deploying from root terraform/)
4. **All guides**: Well-written, accurate, production-tested

### Why No Consolidations?

Separation of concerns is well-executed:
- **RBAC.md** (18KB) would be unwieldy combined with other docs
- **TIMEOUTS.md** (16KB) is comprehensive standalone reference
- **Destroy docs** (2 files) serve different audiences (understanding vs action)

### Future Considerations

As documentation grows with new guides (FAQ, Operations, Monitoring, Security):
- Consider adding **navigation index** at top of main README
- Consider adding **documentation map** showing reading paths
- Keep docs modular and focused (don't create mega-files)

---

**End of Cleanup List**

**Summary**: Minimal cleanup needed. Focus effort on creating new documentation (Phase 1-3) rather than cleaning existing content.
