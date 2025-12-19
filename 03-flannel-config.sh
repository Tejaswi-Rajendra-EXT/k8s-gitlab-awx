#!/bin/bash

# =============================================================================
# Flannel CNI Configuration Script
# Run this script ONLY on the master node
# =============================================================================

echo "Starting Flannel CNI Configuration..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# -------------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------------
FLANNEL_URL="https://raw.githubusercontent.com/flannel-io/flannel/v0.25.5/Documentation/kube-flannel.yml"
FLANNEL_FILE="./kube-flannel.yaml"

# Corporate proxy (used ONLY for download)
HTTP_PROXY="http://10.120.125.146:8080"

# -------------------------------------------------------------------------
# Function to check if kubectl is available
# -------------------------------------------------------------------------
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        print_error "Please ensure the cluster is initialized and kubectl is configured"
        exit 1
    fi

    print_status "kubectl is available and can connect to cluster"
}

# -------------------------------------------------------------------------
# Function to check cluster status
# -------------------------------------------------------------------------
check_cluster_status() {
    print_status "Checking cluster status..."

    echo "=== Cluster Nodes ==="
    kubectl get nodes -o wide

    READY_NODES=$(kubectl get nodes --no-headers | grep -c "Ready")
    TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)

    print_status "Ready nodes: ${READY_NODES}/${TOTAL_NODES}"

    echo "=== System Pods ==="
    kubectl get pods --all-namespaces
}

# -------------------------------------------------------------------------
# Function to deploy Flannel
# -------------------------------------------------------------------------
deploy_flannel() {
    print_status "Deploying Flannel CNI..."

    print_status "Downloading Flannel manifest using proxy..."
    if ! curl -x "${HTTP_PROXY}" -o "${FLANNEL_FILE}" "${FLANNEL_URL}"; then
        print_error "Failed to download Flannel manifest"
        exit 1
    fi

    print_status "Applying Flannel manifest locally..."
    if ! kubectl apply -f "${FLANNEL_FILE}"; then
        print_error "Failed to apply Flannel manifest"
        exit 1
    fi

    print_status "Flannel manifest applied successfully"
}

# -------------------------------------------------------------------------
# Function to wait for Flannel pods
# -------------------------------------------------------------------------
wait_for_flannel() {
    print_status "Waiting for Flannel pods to be ready..."

    if kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s; then
        print_status "Flannel pods are ready"
    else
        print_warning "Flannel pods may not be fully ready yet"
    fi
}

# -------------------------------------------------------------------------
# Function to verify Flannel installation
# -------------------------------------------------------------------------
verify_flannel() {
    print_status "Verifying Flannel installation..."

    echo "=== Flannel Pods ==="
    kubectl get pods -n kube-flannel -o wide

    echo "=== Flannel DaemonSet ==="
    kubectl get daemonset -n kube-flannel

    echo "=== Flannel Logs (first pod) ==="
    FLANNEL_POD=$(kubectl get pods -n kube-flannel --no-headers | head -1 | awk '{print $1}')
    if [[ -n "$FLANNEL_POD" ]]; then
        kubectl logs "$FLANNEL_POD" -n kube-flannel --tail=10
    fi
}

# -------------------------------------------------------------------------
# Function to check network connectivity
# -------------------------------------------------------------------------
check_network_connectivity() {
    print_status "Checking network connectivity..."

    echo "=== Node Network Status ==="
    kubectl get nodes -o wide

    echo "=== Testing Pod Scheduling ==="
    if kubectl run test-pod --image=busybox --rm -i --restart=Never -- sleep 10; then
        print_status "Network connectivity test passed"
    else
        print_warning "Network connectivity test failed"
    fi
}

# -------------------------------------------------------------------------
# Function to check Flannel configuration
# -------------------------------------------------------------------------
check_flannel_config() {
    print_status "Checking Flannel configuration..."

    echo "=== Flannel ConfigMap ==="
    kubectl get configmap kube-flannel-cfg -n kube-flannel -o yaml

    echo "=== Flannel Service ==="
    kubectl get service -n kube-flannel
}

# -------------------------------------------------------------------------
# Function to troubleshoot Flannel
# -------------------------------------------------------------------------
troubleshoot_flannel() {
    print_status "Troubleshooting Flannel..."

    echo "=== Flannel Pod Status ==="
    kubectl describe pods -n kube-flannel

    echo "=== Flannel Events ==="
    kubectl get events -n kube-flannel --sort-by='.lastTimestamp'

    echo "=== Node Conditions ==="
    kubectl describe nodes
}

# -------------------------------------------------------------------------
# Main execution
# -------------------------------------------------------------------------
main() {
    print_status "Starting Flannel CNI Configuration Script..."

    check_kubectl
    check_cluster_status
    deploy_flannel
    wait_for_flannel
    verify_flannel
    check_network_connectivity
    check_flannel_config

    print_status "Flannel CNI configuration completed successfully!"

    read -p "Do you want to run troubleshooting checks? (y/n): " TROUBLESHOOT
    if [[ "$TROUBLESHOOT" == "y" || "$TROUBLESHOOT" == "Y" ]]; then
        troubleshoot_flannel
    fi
}

main "$@"
