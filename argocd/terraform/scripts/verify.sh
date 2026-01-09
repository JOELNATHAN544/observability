#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}ℹ${NC}  $1"; }
log_success() { echo -e "${GREEN}✓${NC}  $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC}  $1"; }
log_error() { echo -e "${RED}✗${NC}  $1"; }

verify_contexts() {
    log_info "Verifying Kubernetes contexts..."
    
    local control_plane=$(terraform output -raw control_plane_context 2>/dev/null || echo "control-plane")
    local workload=$(terraform output -raw workload_context 2>/dev/null | head -1 | cut -d' ' -f1 || echo "workload-1")
    
    # Check control plane context
    if kubectl config get-contexts | grep -q "$control_plane"; then
        log_success "Control plane context found: $control_plane"
    else
        log_error "Control plane context not found: $control_plane"
        return 1
    fi
    
    # Check workload context
    if kubectl config get-contexts | grep -q "$workload"; then
        log_success "Workload context found: $workload"
    else
        log_error "Workload context not found: $workload"
        return 1
    fi
}

verify_namespaces() {
    log_info "Verifying namespaces..."
    
    local control_plane=$(terraform output -raw kubectl_contexts 2>/dev/null | grep control_plane | cut -d'"' -f2 || echo "control-plane")
    local workload=$(terraform output -raw kubectl_contexts 2>/dev/null | grep workload | cut -d'"' -f2 || echo "workload-1")
    
    if kubectl get ns argocd --context="$control_plane" &>/dev/null; then
        log_success "Namespace 'argocd' exists on control plane"
    else
        log_error "Namespace 'argocd' not found on control plane"
        return 1
    fi
    
    if kubectl get ns argocd --context="$workload" &>/dev/null; then
        log_success "Namespace 'argocd' exists on workload cluster"
    else
        log_error "Namespace 'argocd' not found on workload cluster"
        return 1
    fi
}

verify_deployments() {
    log_info "Verifying deployments..."
    
    local control_plane=$(terraform output -raw kubectl_contexts 2>/dev/null | grep control_plane | cut -d'"' -f2 || echo "control-plane")
    local workload=$(terraform output -raw kubectl_contexts 2>/dev/null | grep workload | cut -d'"' -f2 || echo "workload-1")
    
    # Check control plane
    log_info "Control plane deployments:"
    if kubectl get deployment -n argocd --context="$control_plane" &>/dev/null; then
        kubectl get deployment -n argocd --context="$control_plane" --no-headers | while read line; do
            local name=$(echo "$line" | awk '{print $1}')
            local ready=$(echo "$line" | awk '{print $2}')
            if [[ "$ready" == "1/1" ]] || [[ "$ready" == "2/2" ]]; then
                log_success "  $name: Ready ($ready)"
            else
                log_warn "  $name: Not fully ready ($ready)"
            fi
        done
    else
        log_error "  Cannot fetch deployments"
        return 1
    fi
    
    # Check workload
    log_info "Workload cluster deployments:"
    if kubectl get deployment -n argocd --context="$workload" &>/dev/null; then
        kubectl get deployment -n argocd --context="$workload" --no-headers | while read line; do
            local name=$(echo "$line" | awk '{print $1}')
            local ready=$(echo "$line" | awk '{print $2}')
            if [[ "$ready" == "1/1" ]] || [[ "$ready" == "2/2" ]]; then
                log_success "  $name: Ready ($ready)"
            else
                log_warn "  $name: Not fully ready ($ready)"
            fi
        done
    else
        log_error "  Cannot fetch deployments"
        return 1
    fi
}

verify_tls() {
    log_info "Verifying TLS certificates..."
    
    cd "$PROJECT_ROOT"
    
    if [ ! -f "certs/ca.crt" ]; then
        log_warn "CA certificate not found"
        return 0
    fi
    
    if [ ! -f "certs/argocd-server.crt" ]; then
        log_error "Server certificate not found"
        return 1
    fi
    
    if [ ! -f "certs/agent-client.crt" ]; then
        log_error "Agent client certificate not found"
        return 1
    fi
    
    log_success "All certificates present"
    
    # Verify chain
    if openssl verify -CAfile certs/ca.crt certs/argocd-server.crt &>/dev/null; then
        log_success "Server certificate valid"
    else
        log_warn "Server certificate validation failed"
    fi
    
    if openssl verify -CAfile certs/ca.crt certs/agent-client.crt &>/dev/null; then
        log_success "Client certificate valid"
    else
        log_warn "Client certificate validation failed"
    fi
}

verify_secrets() {
    log_info "Verifying Kubernetes secrets..."
    
    local control_plane=$(terraform output -raw kubectl_contexts 2>/dev/null | grep control_plane | cut -d'"' -f2 || echo "control-plane")
    local workload=$(terraform output -raw kubectl_contexts 2>/dev/null | grep workload | cut -d'"' -f2 || echo "workload-1")
    
    # Check control plane secrets
    if kubectl get secret argocd-server-tls -n argocd --context="$control_plane" &>/dev/null; then
        log_success "Server TLS secret found on control plane"
    else
        log_error "Server TLS secret not found on control plane"
    fi
    
    # Check workload secrets
    if kubectl get secret argocd-agent-client-tls -n argocd --context="$workload" &>/dev/null; then
        log_success "Agent client TLS secret found on workload"
    else
        log_error "Agent client TLS secret not found on workload"
    fi
}

verify_connectivity() {
    log_info "Verifying agent connectivity..."
    
    local workload=$(terraform output -raw kubectl_contexts 2>/dev/null | grep workload | cut -d'"' -f2 || echo "workload-1")
    
    # Check agent logs for connection
    local logs=$(kubectl logs -n argocd deployment/argocd-agent --context="$workload" 2>/dev/null | tail -20 || echo "")
    
    if echo "$logs" | grep -qi "connected\|authenticated"; then
        log_success "Agent appears to be connected"
    elif echo "$logs" | grep -qi "error\|failed"; then
        log_warn "Agent may have connection issues - check logs"
    else
        log_info "Agent status unclear - check logs for details"
    fi
}

main() {
    echo ""
    log_info "Argo CD Agent Setup Verification"
    echo ""
    
    cd "$PROJECT_ROOT"
    
    local failed=0
    
    verify_contexts || ((failed++))
    echo ""
    
    verify_namespaces || ((failed++))
    echo ""
    
    verify_deployments || ((failed++))
    echo ""
    
    verify_tls || ((failed++))
    echo ""
    
    verify_secrets || ((failed++))
    echo ""
    
    verify_connectivity
    echo ""
    
    if [ $failed -eq 0 ]; then
        log_success "All verifications passed!"
        return 0
    else
        log_error "$failed verification(s) failed"
        return 1
    fi
}

main "$@"
