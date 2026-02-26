#!/usr/bin/env bash
# deploy-all.sh
# Deploys the entire Secure API Platform using Helm.
# Architecture: Envoy (DDoS) → Kong (JWT/rate-limit/IP) → User Service (FastAPI)
#
# Usage:
#   ./scripts/deploy-all.sh               # full deploy
#   ./scripts/deploy-all.sh --build-image # also build docker image

set -euo pipefail

NAMESPACE="api-platform"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BUILD_IMAGE=false
for arg in "$@"; do [[ "$arg" == "--build-image" ]] && BUILD_IMAGE=true; done

echo "════════════════════════════════════════════════════════════"
echo "  Secure API Platform — Helm Deployment"
echo "  Namespace: $NAMESPACE"
echo "════════════════════════════════════════════════════════════"

# ── 0. Namespace ──────────────────────────────────────────────────────────────
echo ""
echo "▶ [0/4] Creating namespace '$NAMESPACE' (if not exists)..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# ── 1. Build Docker image (optional) ─────────────────────────────────────────
if $BUILD_IMAGE; then
  echo ""
  echo "▶ [1/4] Building user-service Docker image inside minikube..."
  eval "$(minikube docker-env)"
  docker build -t user-service:latest "$ROOT_DIR/microservice"
else
  echo ""
  echo "▶ [1/4] Skipping Docker build (use --build-image to rebuild)"
fi

# ── 2. Deploy user-service via Helm ──────────────────────────────────────────
echo ""
echo "▶ [2/4] Deploying user-service (Helm)..."
helm upgrade --install user-service "$ROOT_DIR/helm/user-service" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait --timeout 3m \
  --set "image.repository=user-service" \
  --set "image.tag=latest" \
  --set "image.pullPolicy=IfNotPresent"

echo "  ✓ user-service deployed"

# ── 3. Deploy Kong via Helm ───────────────────────────────────────────────────
echo ""
echo "▶ [3/4] Deploying Kong API Gateway (Helm)..."
helm upgrade --install kong-gateway "$ROOT_DIR/helm/kong" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait --timeout 3m

echo "  ✓ kong-gateway deployed"

# ── 4. Deploy Envoy DDoS proxy via Helm ──────────────────────────────────────
echo ""
echo "▶ [4/4] Deploying Envoy DDoS proxy (Helm)..."
helm upgrade --install envoy-ddos "$ROOT_DIR/helm/envoy" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --wait --timeout 3m

echo "  ✓ envoy-ddos deployed"

# ── Status ────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Deployment complete"
echo "════════════════════════════════════════════════════════════"
echo ""
helm list -n "$NAMESPACE"
echo ""
kubectl get pods -n "$NAMESPACE"
echo ""

MINIKUBE_IP=$(minikube ip 2>/dev/null || echo "127.0.0.1")
echo "  External entrypoint (Envoy): http://$MINIKUBE_IP:30082"
echo "  Inside minikube:"
echo "    minikube ssh 'curl http://$MINIKUBE_IP:30082/health'"
echo ""
echo "  Test with:  ./test-user-service-direct.sh"
