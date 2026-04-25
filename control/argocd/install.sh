#!/bin/bash
set -euo pipefail

# Installs ArgoCD on the control cluster and applies the app-of-apps
# Usage: KUBECONFIG=~/.kube/oasis-control.kubeconfig ./control/argocd/install.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing ArgoCD..."
helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo
helm upgrade --install argocd argo/argo-cd \
  --create-namespace -n argocd \
  --wait --timeout 5m

echo "Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=Available deployment/argocd-server -n argocd --timeout=120s

echo "Applying ingress..."
kubectl apply -f "$SCRIPT_DIR/server-ingress.yml"

echo "Applying app-of-apps..."
kubectl apply -f "$SCRIPT_DIR/app-of-apps.yml"

echo "ArgoCD installed. Get initial admin password with:"
echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
