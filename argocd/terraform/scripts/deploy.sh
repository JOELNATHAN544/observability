#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}ℹ${NC}  $1"
}

log_success() {
    echo -e "${GREEN}✓${NC}  $1"
}

log_warn() {
    echo -e "${YELLOW}⚠${NC}  $1"
}

log_error() {
    echo -e "${RED}✗${NC}  $1"
}

main() {
    log_info "Starting Argo CD Agent Deployment"
    
    cd "$PROJECT_ROOT"
    
    # Check prerequisites
    log_info "Checking prerequisites..."
    
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed"
        exit 1
    fi
    log_success "Terraform found: $(terraform version | head -n 1)"
    
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed"
        exit 1
    fi
    log_success "kubectl found: $(kubectl version --client --short)"
    
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed"
        exit 1
    fi
    log_success "Helm found: $(helm version --short)"
    
    # Check terraform.tfvars exists
    if [ ! -f "terraform.tfvars" ]; then
        log_warn "terraform.tfvars not found"
        log_info "Creating from example..."
        cp terraform.tfvars.example terraform.tfvars
        log_warn "Please edit terraform.tfvars with your cluster details"
        exit 1
    fi
    
    log_success "terraform.tfvars found"
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    log_success "Terraform initialized"
    
    # Validate configuration
    log_info "Validating Terraform configuration..."
    terraform validate
    log_success "Configuration is valid"
    
    # Plan deployment
    log_info "Planning deployment..."
    terraform plan -out=tfplan
    
    # Ask for confirmation
    echo ""
    read -p "Do you want to proceed with the deployment? (yes/no): " -r confirm
    if [[ ! $confirm =~ ^[Yy][Ee][Ss]$ ]]; then
        log_warn "Deployment cancelled"
        rm -f tfplan
        exit 0
    fi
    
    # Apply configuration
    log_info "Applying configuration..."
    terraform apply tfplan
    
    log_success "Deployment complete!"
    
    # Display outputs
    echo ""
    log_info "Deployment Summary:"
    terraform output -json | jq -r 'to_entries[] | "\(.key): \(.value.value)"'
    
    # Provide next steps
    echo ""
    log_info "Next Steps:"
    echo "  1. Verify the setup:"
    echo "     make verify"
    echo ""
    echo "  2. Check agent logs:"
    echo "     make logs"
    echo ""
    echo "  3. View certificates:"
    echo "     make certs-info"
    echo ""
}

main "$@"
