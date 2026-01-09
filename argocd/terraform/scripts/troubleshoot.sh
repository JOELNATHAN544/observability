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

show_pod_events() {
    local context=$1
    local pod=$2
    
    log_info "Pod events for $pod (context: $context):"
    kubectl describe pod "$pod" -n argocd --context="$context" 2>/dev/null | grep -A 20 "^Events:" || echo "  No events found"
    echo ""
}

check_agent_logs() {
    local workload=$(terraform output -raw kubectl_contexts 2>/dev/null | grep workload | cut -d'"' -f2 || echo "workload-1")
    
    log_info "Recent agent logs:"
    kubectl logs -n argocd deployment/argocd-agent --context="$workload" --tail=50 2>/dev/null || log_error "Cannot fetch logs"
    echo ""
}

check_principal_logs() {
    local control_plane=$(terraform output -raw kubectl_contexts 2>/dev/null | grep control_plane | cut -d'"' -f2 || echo "control-plane")
    
    log_info "Recent principal server logs:"
    kubectl logs -n argocd deployment/argocd-server --context="$control_plane" --tail=50 2>/dev/null || log_error "Cannot fetch logs"
    echo ""
}

check_network_connectivity() {
    local workload=$(terraform output -raw kubectl_contexts 2>/dev/null | grep workload | cut -d'"' -f2 || echo "workload-1")
    local principal_addr=$(terraform output -raw principal_server_address 2>/dev/null || echo "argocd-cp.local")
    local principal_port=$(terraform output -raw principal_server_port 2>/dev/null || echo "443")
    
    log_info "Testing network connectivity to principal..."
    
    # Get agent pod name
    local agent_pod=$(kubectl get pods -n argocd -l app=argocd-agent --context="$workload" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$agent_pod" ]; then
        log_error "Agent pod not found"
        return 1
    fi
    
    log_info "Testing DNS resolution from agent pod..."
    kubectl exec -it "$agent_pod" -n argocd --context="$workload" -- nslookup "$principal_addr" 2>/dev/null || {
        log_warn "DNS resolution failed for $principal_addr"
        return 1
    }
    
    log_info "Testing TCP connectivity to principal..."
    kubectl exec -it "$agent_pod" -n argocd --context="$workload" -- \
        timeout 5 bash -c "echo > /dev/tcp/$principal_addr/$principal_port" 2>/dev/null && \
        log_success "TCP connection successful" || \
        log_error "TCP connection failed to $principal_addr:$principal_port"
    
    echo ""
}

check_certificate_validity() {
    cd "$PROJECT_ROOT"
    
    log_info "Checking certificate validity..."
    
    if [ -f "certs/argocd-server.crt" ]; then
        log_info "Server certificate expiration:"
        openssl x509 -in certs/argocd-server.crt -noout -dates 2>/dev/null || log_error "Cannot read certificate"
    fi
    
    if [ -f "certs/agent-client.crt" ]; then
        log_info "Agent client certificate expiration:"
        openssl x509 -in certs/agent-client.crt -noout -dates 2>/dev/null || log_error "Cannot read certificate"
    fi
    
    echo ""
}

list_resources() {
    local control_plane=$(terraform output -raw kubectl_contexts 2>/dev/null | grep control_plane | cut -d'"' -f2 || echo "control-plane")
    local workload=$(terraform output -raw kubectl_contexts 2>/dev/null | grep workload | cut -d'"' -f2 || echo "workload-1")
    
    log_info "Control plane resources:"
    kubectl get all -n argocd --context="$control_plane" 2>/dev/null || log_error "Cannot fetch resources"
    echo ""
    
    log_info "Workload cluster resources:"
    kubectl get all -n argocd --context="$workload" 2>/dev/null || log_error "Cannot fetch resources"
    echo ""
}

show_configuration() {
    cd "$PROJECT_ROOT"
    
    log_info "Configuration summary:"
    terraform output 2>/dev/null | head -20 || log_error "Cannot fetch outputs"
    echo ""
}

show_tls_handshake() {
    local workload=$(terraform output -raw kubectl_contexts 2>/dev/null | grep workload | cut -d'"' -f2 || echo "workload-1")
    local principal_addr=$(terraform output -raw principal_server_address 2>/dev/null || echo "argocd-cp.local")
    local principal_port=$(terraform output -raw principal_server_port 2>/dev/null || echo "443")
    
    log_info "Testing TLS handshake..."
    
    local agent_pod=$(kubectl get pods -n argocd -l app=argocd-agent --context="$workload" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$agent_pod" ]; then
        log_error "Agent pod not found"
        return 1
    fi
    
    kubectl exec -it "$agent_pod" -n argocd --context="$workload" -- \
        openssl s_client -connect "$principal_addr:$principal_port" -showcerts < /dev/null 2>/dev/null | head -30 || \
        log_warn "Could not complete TLS handshake test"
    
    echo ""
}

main() {
    echo ""
    log_info "Argo CD Agent Troubleshooting"
    echo ""
    
    cd "$PROJECT_ROOT"
    
    # Show menu
    echo "Select what to check:"
    echo "  1. Agent logs"
    echo "  2. Principal logs"
    echo "  3. Pod events"
    echo "  4. Network connectivity"
    echo "  5. Certificate validity"
    echo "  6. TLS handshake"
    echo "  7. List all resources"
    echo "  8. Show configuration"
    echo "  9. Full diagnostic report"
    echo "  0. Exit"
    echo ""
    
    read -p "Enter your choice (0-9): " choice
    
    case $choice in
        1) check_agent_logs ;;
        2) check_principal_logs ;;
        3) 
            local workload=$(terraform output -raw kubectl_contexts 2>/dev/null | grep workload | cut -d'"' -f2 || echo "workload-1")
            local pod=$(kubectl get pods -n argocd -l app=argocd-agent --context="$workload" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
            if [ -n "$pod" ]; then
                show_pod_events "$workload" "$pod"
            else
                log_error "Agent pod not found"
            fi
            ;;
        4) check_network_connectivity ;;
        5) check_certificate_validity ;;
        6) show_tls_handshake ;;
        7) list_resources ;;
        8) show_configuration ;;
        9) 
            log_info "Running full diagnostic report..."
            check_agent_logs
            check_principal_logs
            check_network_connectivity
            check_certificate_validity
            list_resources
            ;;
        0) exit 0 ;;
        *) log_error "Invalid choice" ;;
    esac
}

main "$@"
