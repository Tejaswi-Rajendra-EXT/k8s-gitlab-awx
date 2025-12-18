#!/bin/bash
set -e

echo "Starting Nginx Ingress Controller Installation..."

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
err() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ------------------------------------------------------------------
# Verify kubectl access
# ------------------------------------------------------------------
log "Checking cluster access..."
kubectl cluster-info >/dev/null 2>&1 || err "kubectl cannot access cluster"

# ------------------------------------------------------------------
# Install ingress-nginx
# ------------------------------------------------------------------
log "Installing ingress-nginx..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/baremetal/deploy.yaml

# ------------------------------------------------------------------
# Force single replica (important for bare metal)
# ------------------------------------------------------------------
log "Scaling ingress controller to 1 replica..."
kubectl scale deployment ingress-nginx-controller -n ingress-nginx --replicas=1

# ------------------------------------------------------------------
# Wait for controller readiness
# ------------------------------------------------------------------
log "Waiting for ingress controller to be Ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s || err "Ingress controller did not become ready"

# ------------------------------------------------------------------
# DISABLE admission webhook (CRITICAL FIX)
# ------------------------------------------------------------------
log "Disabling ingress admission webhook (on-prem safe)..."
kubectl delete validatingwebhookconfiguration ingress-nginx-admission --ignore-not-found

# ------------------------------------------------------------------
# Ensure NodePort
# ------------------------------------------------------------------
log "Ensuring NodePort service..."
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec":{"type":"NodePort"}}' >/dev/null

# ------------------------------------------------------------------
# Show status
# ------------------------------------------------------------------
log "Verifying ingress-nginx pods..."
kubectl get pods -n ingress-nginx

# ------------------------------------------------------------------
# Fetch NodePort info
# ------------------------------------------------------------------
log "Fetching NodePort access information..."

NODE_IP=$(kubectl get nodes -o wide | grep -v NAME | head -1 | awk '{print $6}')
HTTP_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
HTTPS_PORT=$(kubectl get svc ingress-nginx-controller -n ingress-nginx \
  -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

echo ""
log "Ingress Access Information:"
echo "  Node IP       : $NODE_IP"
echo "  HTTP NodePort : $HTTP_PORT"
echo "  HTTPS NodePort: $HTTPS_PORT"
echo ""

# ------------------------------------------------------------------
# Optional ingress test
# ------------------------------------------------------------------
read -p "Run ingress test? (y/n): " RUN_TEST
if [[ "$RUN_TEST" =~ ^[Yy]$ ]]; then
    log "Running ingress test..."

    kubectl delete ingress test-ingress --ignore-not-found
    kubectl delete svc test-app --ignore-not-found
    kubectl delete deployment test-app --ignore-not-found

    kubectl create deployment test-app --image=nginx:alpine || err "Failed to create test deployment"
    kubectl expose deployment test-app --port=80 || err "Failed to expose test service"

cat <<EOF | kubectl apply -f - || err "Failed to create test ingress"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: test-ingress
spec:
  ingressClassName: nginx
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: test-app
            port:
              number: 80
EOF

    sleep 10

    log "Testing ingress via NodePort..."
    if curl -s http://$NODE_IP:$HTTP_PORT >/dev/null; then
        log "Ingress test PASSED"
    else
        err "Ingress test FAILED"
    fi

    kubectl delete ingress test-ingress
    kubectl delete svc test-app
    kubectl delete deployment test-app
fi

log "Nginx Ingress setup completed successfully"
