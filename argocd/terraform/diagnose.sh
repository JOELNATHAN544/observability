#!/bin/bash
# ArgoCD Deployment Diagnostics Script

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}ArgoCD Deployment Diagnostics${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

CONTROL_PLANE_KUBECONFIG="/home/ubuntu/cluster/cluster2.yaml"
CONTROL_PLANE_CONTEXT="cluster-2"
WORKLOAD_KUBECONFIG="/home/ubuntu/cluster/cluster1.yaml"
WORKLOAD_CONTEXT="workload"

# Function to run kubectl with error handling
run_kubectl_cp() {
    kubectl --kubeconfig="$CONTROL_PLANE_KUBECONFIG" --context="$CONTROL_PLANE_CONTEXT" "$@"
}

run_kubectl_wl() {
    kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" --context="$WORKLOAD_CONTEXT" "$@"
}

# 1. Check Helm release status
echo -e "${YELLOW}1. Checking Helm Release Status${NC}"
echo "Listing Helm releases in argocd namespace..."
helm --kubeconfig="$CONTROL_PLANE_KUBECONFIG" --kube-context="$CONTROL_PLANE_CONTEXT" list -n argocd 2>&1 || echo "No releases found or namespace doesn't exist"

echo ""
echo "Getting detailed status of argocd release (if exists)..."
helm --kubeconfig="$CONTROL_PLANE_KUBECONFIG" --kube-context="$CONTROL_PLANE_CONTEXT" status argocd -n argocd 2>&1 || echo "Release not found"

echo ""

# 2. Check namespace existence
echo -e "${YELLOW}2. Checking ArgoCD Namespace${NC}"
echo "Control plane cluster:"
run_kubectl_cp get namespace argocd -o yaml 2>&1 || echo "Namespace doesn't exist"

echo ""

# 3. Check pods in argocd namespace
echo -e "${YELLOW}3. Checking Pod Status${NC}"
echo "Control plane pods:"
run_kubectl_cp get pods -n argocd 2>&1 || echo "Cannot get pods or namespace doesn't exist"

echo ""

# 4. Check pod events
echo -e "${YELLOW}4. Checking Events in ArgoCD Namespace${NC}"
run_kubectl_cp get events -n argocd --sort-by='.lastTimestamp' 2>&1 || echo "Cannot get events"

echo ""

# 5. Check specific pod failures
echo -e "${YELLOW}5. Checking Failed/Pending Pods${NC}"
FAILED_PODS=$(run_kubectl_cp get pods -n argocd --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null || echo "")

if [ -n "$FAILED_PODS" ]; then
    for pod in $FAILED_PODS; do
        echo ""
        echo "Describing $pod:"
        run_kubectl_cp describe $pod -n argocd
        echo ""
        echo "Logs from $pod:"
        run_kubectl_cp logs $pod -n argocd --all-containers=true 2>&1 || echo "Cannot get logs"
    done
else
    echo "No failed pods found (or namespace doesn't exist)"
fi

echo ""

# 6. Check workload cluster authentication
echo -e "${YELLOW}6. Testing Workload Cluster Authentication${NC}"
echo "Attempting to access workload cluster..."
echo ""
echo "Available contexts in workload kubeconfig:"
kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" config get-contexts

echo ""
echo "Attempting to get nodes:"
run_kubectl_wl get nodes 2>&1 || {
    echo -e "${RED}✗ Cannot authenticate to workload cluster${NC}"
    echo ""
    echo "Checking current context:"
    kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" config current-context
    echo ""
    echo "Checking user info:"
    kubectl --kubeconfig="$WORKLOAD_KUBECONFIG" config view --minify
}

echo ""

# 7. Check RBAC permissions
echo -e "${YELLOW}7. Checking Current User Permissions${NC}"
echo "Control plane cluster - Can I create namespaces?"
run_kubectl_cp auth can-i create namespaces 2>&1 || echo "Permission check failed"

echo ""
echo "Workload cluster - Can I create namespaces?"
run_kubectl_wl auth can-i create namespaces 2>&1 || echo "Permission check failed"

echo ""
echo "Workload cluster - Can I create clusterroles?"
run_kubectl_wl auth can-i create clusterroles 2>&1 || echo "Permission check failed"

echo ""

# 8. Check Helm release history
echo -e "${YELLOW}8. Checking Helm Release History${NC}"
helm --kubeconfig="$CONTROL_PLANE_KUBECONFIG" --kube-context="$CONTROL_PLANE_CONTEXT" history argocd -n argocd 2>&1 || echo "No history found"

echo ""

# 9. Check for resource quota or limit issues
echo -e "${YELLOW}9. Checking Resource Constraints${NC}"
echo "Resource quotas in argocd namespace:"
run_kubectl_cp get resourcequota -n argocd 2>&1 || echo "No resource quotas or namespace doesn't exist"

echo ""
echo "Limit ranges in argocd namespace:"
run_kubectl_cp get limitrange -n argocd 2>&1 || echo "No limit ranges or namespace doesn't exist"

echo ""

# 10. Check PVC status
echo -e "${YELLOW}10. Checking Persistent Volume Claims${NC}"
run_kubectl_cp get pvc -n argocd 2>&1 || echo "No PVCs or namespace doesn't exist"

echo ""

# 11. Get cluster info
echo -e "${YELLOW}11. Cluster Information${NC}"
echo "Control plane cluster info:"
run_kubectl_cp cluster-info

echo ""
echo "Control plane cluster version:"
run_kubectl_cp version --short 2>&1 || run_kubectl_cp version

echo ""

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Diagnostic Complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo "Summary of findings will help identify the root cause."
echo ""
echo "Common issues to check:"
echo "1. Pod ImagePullBackOff - Check image availability"
echo "2. Pod CrashLoopBackOff - Check pod logs above"
echo "3. Pending pods - Check PVC or node resources"
echo "4. Workload cluster 'Unauthorized' - Check kubeconfig and RBAC"
