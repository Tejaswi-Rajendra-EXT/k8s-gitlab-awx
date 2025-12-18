#!/bin/bash
set -euo pipefail

# =============================================================================
# Kubernetes Installation Script (Rocky Linux 9)
# Assumes script is ALWAYS run as root
# =============================================================================

echo "Starting Kubernetes Installation..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status()  { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# -------------------------------------------------------------------------
# Proxy configuration (CORPORATE NETWORK)
# -------------------------------------------------------------------------
HTTP_PROXY="http://10.120.125.146:8080"
HTTPS_PROXY="http://10.120.125.146:8080"
NO_PROXY="localhost,127.0.0.1,10.3.60.0/24,10.244.0.0/16,10.96.0.0/12"

export HTTP_PROXY HTTPS_PROXY NO_PROXY

configure_proxy_systemd() {
    print_status "Configuring proxy for containerd and kubelet..."

    # containerd proxy
    mkdir -p /etc/systemd/system/containerd.service.d
    cat <<EOF >/etc/systemd/system/containerd.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF

    # kubelet proxy
    mkdir -p /etc/systemd/system/kubelet.service.d
    cat <<EOF >/etc/systemd/system/kubelet.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF

    systemctl daemon-reexec
    systemctl daemon-reload
}

# -------------------------------------------------------------------------
# Disable swap (mandatory for Kubernetes)
# -------------------------------------------------------------------------
disable_swap() {
    print_status "Disabling swap..."
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab
}

# -------------------------------------------------------------------------
# Kernel modules & sysctl
# -------------------------------------------------------------------------
configure_kernel() {
    print_status "Configuring kernel modules and sysctl..."

    cat <<EOF >/etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

    modprobe overlay
    modprobe br_netfilter

    cat <<EOF >/etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    sysctl --system
}

# -------------------------------------------------------------------------
# Install containerd
# -------------------------------------------------------------------------
install_containerd() {
    print_status "Installing containerd..."

    dnf install -y yum-utils device-mapper-persistent-data lvm2
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y containerd.io

    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

    systemctl enable --now containerd
}

# -------------------------------------------------------------------------
# Install Kubernetes packages (OFFICIAL repo)
# -------------------------------------------------------------------------
install_kubernetes() {
    print_status "Installing Kubernetes packages..."

    cat <<EOF >/etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF

    dnf install -y kubelet kubeadm kubectl
    systemctl enable kubelet
}

# -------------------------------------------------------------------------
# Verify installation
# -------------------------------------------------------------------------
verify_installation() {
    print_status "Verifying installation..."

    kubeadm version
    kubelet --version
    kubectl version --client
    systemctl status containerd --no-pager
}

# -------------------------------------------------------------------------
# Initialize master
# -------------------------------------------------------------------------
init_master() {
    print_status "Initializing Kubernetes master..."

    print_status "Pre-pulling Kubernetes images..."
    kubeadm config images pull

    kubeadm init --pod-network-cidr=10.244.0.0/16

    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown root:root $HOME/.kube/config

    print_status "Master initialized successfully"
    print_warning "Save the join command for worker nodes!"
}

# -------------------------------------------------------------------------
# Join worker
# -------------------------------------------------------------------------
join_worker() {
    print_warning "Paste the kubeadm join command from master:"
    read -r JOIN_CMD
    if [[ -z "$JOIN_CMD" ]]; then
        print_error "Join command cannot be empty"
        exit 1
    fi
    $JOIN_CMD
}

# -------------------------------------------------------------------------
# MAIN
# -------------------------------------------------------------------------
main() {
    print_warning "Select node type:"
    echo "1) Master"
    echo "2) Worker"
    read -p "Enter choice (1 or 2): " NODE_CHOICE

    case "$NODE_CHOICE" in
        1) NODE_TYPE="master" ;;
        2) NODE_TYPE="worker" ;;
        *) print_error "Invalid choice"; exit 1 ;;
    esac

    print_status "Configuring $NODE_TYPE node..."

    disable_swap
    configure_kernel
    install_containerd
    configure_proxy_systemd
    systemctl restart containerd

    install_kubernetes
    systemctl restart kubelet

    verify_installation

    if [[ "$NODE_TYPE" == "master" ]]; then
        read -p "Initialize master now? (y/n): " INIT
        [[ "$INIT" =~ ^[Yy]$ ]] && init_master
    else
        read -p "Join worker to cluster now? (y/n): " JOIN
        [[ "$JOIN" =~ ^[Yy]$ ]] && join_worker
    fi

    print_status "Kubernetes setup completed"
}

main
