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

# Function to check if kubectl is available
check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    # Check if kubectl can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        print_error "Please ensure the cluster is initialized and kubectl is configured"
        exit 1
    fi

    print_status "kubectl is available and can connect to cluster"
}

# Function to check cluster status
check_cluster_status() {
    print_status "Checking cluster status..."

    # Check nodes
    echo "=== Cluster Nodes ==="
    kubectl get nodes -o wide

    # Check if nodes are ready
    READY_NODES=$(kubectl get nodes --no-headers | grep -c "Ready")
    TOTAL_NODES=$(kubectl get nodes --no-headers | wc -l)

    print_status "Ready nodes: ${READY_NODES}/${TOTAL_NODES}"

    if [[ $READY_NODES -eq 0 ]]; then
        print_error "No nodes are ready. Please check cluster initialization."
        exit 1
    fi

    # Check if pods are running
    echo "=== System Pods ==="
    kubectl get pods --all-namespaces
}

# Function to deploy Flannel
deploy_flannel() {
    print_status "Deploying Flannel CNI..."

    # Download and apply Flannel manifest
    kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml

    print_status "Flannel manifest applied successfully"
}

# Function to wait for Flannel pods
wait_for_flannel() {
    print_status "Waiting for Flannel pods to be ready..."

    # Wait for Flannel daemonset to be ready
    kubectl wait --for=condition=ready pod -l app=flannel -n kube-flannel --timeout=300s

    if [[ $? -eq 0 ]]; then
        print_status "Flannel pods are ready"
    else
        print_warning "Flannel pods may not be fully ready yet"
    fi
}

# Function to verify Flannel installation
verify_flannel() {
    print_status "Verifying Flannel installation..."

    # Check Flannel pods
    echo "=== Flannel Pods ==="
    kubectl get pods -n kube-flannel -o wide

    # Check Flannel daemonset
    echo "=== Flannel DaemonSet ==="
    kubectl get daemonset -n kube-flannel

    # Check Flannel logs
    echo "=== Flannel Logs (first pod) ==="
    FLANNEL_POD=$(kubectl get pods -n kube-flannel --no-headers | head -1 | awk '{print $1}')
    if [[ -n "$FLANNEL_POD" ]]; then
        kubectl logs $FLANNEL_POD -n kube-flannel --tail=10
    fi
}

# Function to check network connectivity
check_network_connectivity() {
    print_status "Checking network connectivity..."

    # Check if nodes can communicate
    echo "=== Node Network Status ==="
    kubectl get nodes -o wide

    # Check if pods can be scheduled
    echo "=== Testing Pod Scheduling ==="
    kubectl run test-pod --image=busybox --rm -i --restart=Never -- sleep 10

    if [[ $? -eq 0 ]]; then
        print_status "Network connectivity test passed"
    else
        print_warning "Network connectivity test failed"
    fi
}

# Function to check Flannel configuration
check_flannel_config() {
    print_status "Checking Flannel configuration..."

    # Check Flannel configmap
    echo "=== Flannel ConfigMap ==="
    kubectl get configmap kube-flannel-cfg -n kube-flannel -o yaml

    # Check Flannel service
    echo "=== Flannel Service ==="
    kubectl get service -n kube-flannel
}

# Function to troubleshoot Flannel
troubleshoot_flannel() {
    print_status "Troubleshooting Flannel..."

    # Check Flannel pod status
    echo "=== Flannel Pod Status ==="
    kubectl describe pods -n kube-flannel

    # Check Flannel events
    echo "=== Flannel Events ==="
    kubectl get events -n kube-flannel --sort-by='.lastTimestamp'

    # Check node conditions
    echo "=== Node Conditions ==="
    kubectl describe nodes
}

# Main execution
main() {
    print_status "Starting Flannel CNI Configuration Script..."

    # Check prerequisites
    check_kubectl
    check_cluster_status

    # Deploy Flannel
    deploy_flannel

    # Wait for Flannel to be ready
    wait_for_flannel

    # Verify installation
    verify_flannel

    # Check network connectivity
    check_network_connectivity

    # Check configuration
    check_flannel_config

    print_status "Flannel CNI configuration completed successfully!"

    # Ask if user wants to troubleshoot
    read -p "Do you want to run troubleshooting checks? (y/n): " TROUBLESHOOT
    if [[ "$TROUBLESHOOT" == "y" || "$TROUBLESHOOT" == "Y" ]]; then
        troubleshoot_flannel
    fi

    print_status "Next steps:"
    echo "  1. Run 04-nginx-ingress.sh on master node"
    echo "  2. Run 05-gitlab-deployment.yaml on master node"
    echo "  3. Run 06-awx-deployment.yaml on master node"
    echo "  4. Run 07-ingress-rules.yaml on master node"
    echo "  5. Run 08-verification.sh on master node"
}

# Run main function
main "$@"
