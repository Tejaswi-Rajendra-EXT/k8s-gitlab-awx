#!/bin/bash

# =============================================================================
# VM Setup and Network Configuration Script
# Run this script on BOTH master and worker nodes
# =============================================================================

echo "Starting VM Setup and Network Configuration..."

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

# Function to check if running as root
#check_root() {
#    if [[ $EUID -eq 0 ]]; then
#        print_warning "This script should not be run as root. Please run as a regular user with sudo privileges."
#        exit 1
#    fi
#}

# Function to update system
update_system() {
    print_status "Updating system packages..."
    sudo dnf update -y
    sudo dnf install -y curl wget vim net-tools telnet bind-utils
    print_status "System updated successfully"
}

# Function to configure hostname
configure_hostname() {
    local node_type=$1
    local node_name="k8s-${node_type}"

    print_status "Configuring hostname for ${node_type} node..."
    sudo hostnamectl set-hostname ${node_name}
    echo "127.0.0.1 ${node_name}" | sudo tee -a /etc/hosts
    print_status "Hostname configured as ${node_name}"
}

# Function to configure /etc/hosts
configure_hosts() {
    print_status "Configuring /etc/hosts file..."
    print_warning "Please provide the IP addresses for master and worker nodes:"

    read -p "Enter Master Node IP: " MASTER_IP
    read -p "Enter Worker Node IP: " WORKER_IP

    # Backup original hosts file
    sudo cp /etc/hosts /etc/hosts.backup

    # Add entries to hosts file
    echo "${MASTER_IP} k8s-master" | sudo tee -a /etc/hosts
    echo "${WORKER_IP} k8s-worker" | sudo tee -a /etc/hosts

    print_status "Hosts file configured with:"
    echo "  Master: ${MASTER_IP} -> k8s-master"
    echo "  Worker: ${WORKER_IP} -> k8s-worker"
}

# Function to configure firewall
configure_firewall() {
    local node_type=$1

    print_status "Configuring firewall for ${node_type} node..."

    # Common ports for both nodes
    sudo firewall-cmd --permanent --add-port=10250/tcp
    sudo firewall-cmd --permanent --add-port=30000-32767/tcp
    sudo firewall-cmd --permanent --add-port=8285/udp
    sudo firewall-cmd --permanent --add-port=8472/udp
    sudo firewall-cmd --permanent --add-port=80/tcp
    sudo firewall-cmd --permanent --add-port=443/tcp

    # Master node specific ports
    if [[ "$node_type" == "master" ]]; then
        sudo firewall-cmd --permanent --add-port=6443/tcp
        sudo firewall-cmd --permanent --add-port=2379-2380/tcp
        sudo firewall-cmd --permanent --add-port=10251/tcp
        sudo firewall-cmd --permanent --add-port=10252/tcp
        sudo firewall-cmd --permanent --add-port=10255/tcp
    fi

    sudo firewall-cmd --reload
    print_status "Firewall configured successfully"
}

# Function to test network connectivity
test_connectivity() {
    print_status "Testing network connectivity..."

    # Test DNS resolution
    print_status "Testing DNS resolution..."
    nslookup k8s-master
    nslookup k8s-worker

    # Test ping connectivity
    print_status "Testing ping connectivity..."
    ping -c 3 k8s-master
    ping -c 3 k8s-worker

    # Test specific ports
    print_status "Testing port connectivity..."
    telnet k8s-master 22
    telnet k8s-worker 22

    if [[ "$1" == "master" ]]; then
        telnet k8s-worker 10250
    fi
}

# Function to configure kernel modules and sysctl
configure_kernel() {
    print_status "Configuring kernel modules and sysctl..."

    # Disable swap (required for Kubernetes)
    print_status "Disabling swap..."
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
    print_status "Swap disabled successfully"

    # Load required modules
    cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

    # Configure sysctl
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 0
EOF

    # Apply sysctl changes
    sudo sysctl --system
    print_status "Kernel configuration completed"
}

# Function to check Zscaler impact
check_zscaler() {
    print_status "Checking for Zscaler impact..."

    # Check if Zscaler is running
    if pgrep -f zscaler > /dev/null; then
        print_warning "Zscaler is detected. This may affect Kubernetes networking."
        print_warning "You may need to configure Zscaler exceptions for Kubernetes ports."
    else
        print_status "No Zscaler detected"
    fi

    # Check proxy settings
    if [[ -n "$HTTP_PROXY" || -n "$HTTPS_PROXY" || -n "$NO_PROXY" ]]; then
        print_warning "Proxy environment variables detected:"
        echo "  HTTP_PROXY: $HTTP_PROXY"
        echo "  HTTPS_PROXY: $HTTPS_PROXY"
        echo "  NO_PROXY: $NO_PROXY"
    fi

    # Check system proxy configuration
    if [[ -f /etc/environment ]]; then
        if grep -i proxy /etc/environment > /dev/null; then
            print_warning "Proxy configuration found in /etc/environment"
            grep -i proxy /etc/environment
        fi
    fi
}

# Main execution
main() {
    print_status "Starting VM Setup Script..."

    # Check if running as root
   # check_root

    # Determine node type
    print_warning "Please specify the node type:"
    echo "1) master"
    echo "2) worker"
    read -p "Enter choice (1 or 2): " NODE_CHOICE

    case $NODE_CHOICE in
        1) NODE_TYPE="master" ;;
        2) NODE_TYPE="worker" ;;
        *) print_error "Invalid choice. Exiting."; exit 1 ;;
    esac

    print_status "Configuring ${NODE_TYPE} node..."

    # Execute setup steps
    update_system
    configure_hostname $NODE_TYPE
    configure_hosts
    configure_firewall $NODE_TYPE
    configure_kernel
    check_zscaler

    print_status "VM setup completed successfully!"
    print_status "Next steps:"
    echo "  1. Run 02-kubernetes-install.sh on both nodes"
    echo "  2. Run 03-flannel-config.sh on master node"
    echo "  3. Run 04-nginx-ingress.sh on master node"
    echo "  4. Run 05-gitlab-deployment.yaml on master node"
    echo "  5. Run 06-awx-deployment.yaml on master node"
    echo "  6. Run 07-ingress-rules.yaml on master node"
    echo "  7. Run 08-verification.sh on master node"
}

# Run main function
main "$@"
