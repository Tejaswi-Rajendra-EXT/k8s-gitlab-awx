#!/bin/bash
set -euo pipefail

echo "=============================================="
echo " Installing Kubernetes Storage (Local Path)"
echo "=============================================="

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# -------------------------------------------------------------------
# Pre-checks
# -------------------------------------------------------------------
info "Checking kubectl access..."
kubectl get nodes >/dev/null 2>&1 || error "kubectl not working"

# -------------------------------------------------------------------
# Install Local Path Provisioner
# -------------------------------------------------------------------
info "Installing local-path-provisioner..."

kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml

info "Waiting for local-path-provisioner pod..."
kubectl wait --for=condition=ready pod \
  -l app=local-path-provisioner \
  -n local-path-storage \
  --timeout=120s || error "local-path-provisioner did not start"

# -------------------------------------------------------------------
# Make it default StorageClass
# -------------------------------------------------------------------
info "Setting local-path as default StorageClass..."

kubectl patch storageclass local-path \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# -------------------------------------------------------------------
# Verify StorageClass
# -------------------------------------------------------------------
info "Verifying StorageClass..."
kubectl get storageclass

DEFAULT_SC=$(kubectl get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}' | grep true || true)

[[ -z "$DEFAULT_SC" ]] && error "No default StorageClass set"

# -------------------------------------------------------------------
# Verify storage path on node
# -------------------------------------------------------------------
info "Verifying node storage directory..."
STORAGE_PATH="/opt/local-path-provisioner"
mkdir -p $STORAGE_PATH || error "Failed to create $STORAGE_PATH"
chmod 777 $STORAGE_PATH

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo ""
info "Storage setup completed successfully 🎉"
echo ""
echo "Next steps:"
echo "1) Re-apply GitLab deployment:"
echo "   kubectl apply -f 05-gitlab-deployment.yaml"
echo ""
echo "2) Watch GitLab pod:"
echo "   kubectl get pods -n gitlab -w"
echo ""
echo "=============================================="
