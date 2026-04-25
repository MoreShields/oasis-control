#!/bin/bash
set -euo pipefail

# Full bootstrap: creates Kind cluster → provisions control cluster on AWS → installs CAPI + ArgoCD
# Usage: ./bootstrap/install.sh

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BOOTSTRAP_CONTEXT="kind-oasis-bootstrap"
CONTROL_KUBECONFIG="$HOME/.kube/oasis-control.kubeconfig"

log() { echo "=== $1 ==="; }
wait_for() {
  local desc="$1"; shift
  echo "  Waiting for $desc..."
  until "$@" 2>/dev/null; do sleep 10; done
  echo "  $desc ready."
}

# ── Phase 1: Bootstrap Kind cluster ──────────────────────────────────────────

log "Phase 1: Bootstrap Kind cluster"

if kind get clusters 2>/dev/null | grep -q oasis-bootstrap; then
  echo "  Kind cluster oasis-bootstrap already exists, skipping creation."
else
  kind create cluster --name oasis-bootstrap
fi
kubectl config use-context "$BOOTSTRAP_CONTEXT"

echo "  Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=120s

echo "  Installing CAPI Operator..."
helm repo add capi-operator https://kubernetes-sigs.github.io/cluster-api-operator 2>/dev/null || true
helm repo update capi-operator
helm upgrade --install capi-operator capi-operator/cluster-api-operator \
  --create-namespace -n capi-operator-system --wait --timeout 5m

echo "  Creating AWS credentials secret..."
"$REPO_ROOT/control/secrets/create-aws-secret.sh"

echo "  Applying CAPI providers..."
kubectl apply -f "$REPO_ROOT/control/providers/namespaces.yml"
kubectl apply -f "$REPO_ROOT/control/providers/coreprovider-cluster-api.yml"
kubectl apply -f "$REPO_ROOT/control/providers/infrastructureprovider-aws.yml"
kubectl apply -f "$REPO_ROOT/control/providers/bootstrapprovider-rke2.yml"
kubectl apply -f "$REPO_ROOT/control/providers/controlplaneprovider-rke2.yml"

echo "  Waiting for providers to be ready..."
sleep 30
wait_for "CoreProvider" bash -c "kubectl get coreproviders cluster-api -n capi-system -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
wait_for "InfrastructureProvider" bash -c "kubectl get infrastructureproviders aws -n aws-infrastructure-system -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
wait_for "BootstrapProvider" bash -c "kubectl get bootstrapproviders rke2 -n rke2-bootstrap-system -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
wait_for "ControlPlaneProvider" bash -c "kubectl get controlplaneproviders rke2 -n rke2-control-plane-system -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"

log "Phase 1 complete: Bootstrap cluster ready"

# ── Phase 2: Create control cluster on AWS ───────────────────────────────────

log "Phase 2: Create control cluster on AWS"

# Clean any stale secrets from previous runs (prevents kubeconfig cert mismatch)
kubectl delete namespace oasis-control --ignore-not-found 2>/dev/null || true

kubectl apply -f "$REPO_ROOT/clusters/oasis-control/cluster.yml"
kubectl apply -f "$REPO_ROOT/clusters/oasis-control/aws-ccm-addon.yml"

echo "  Waiting for AWSCluster to be ready..."
wait_for "AWSCluster" kubectl get awscluster oasis-control -n oasis-control -o jsonpath='{.status.ready}' | grep -q true

echo "  Waiting for all 3 machines to be Running..."
while true; do
  RUNNING=$(kubectl get machines -n oasis-control -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}' 2>/dev/null | grep -c Running || true)
  if [ "$RUNNING" -ge 3 ]; then break; fi
  echo "    $RUNNING/3 machines Running..."
  sleep 30
done

echo "  Extracting control cluster kubeconfig..."
kubectl get secret oasis-control-kubeconfig -n oasis-control \
  -o jsonpath='{.data.value}' | base64 -d > "$CONTROL_KUBECONFIG"

echo "  Verifying control cluster nodes..."
kubectl --kubeconfig "$CONTROL_KUBECONFIG" get nodes

log "Phase 2 complete: Control cluster running"

# ── Phase 3: Install CAPI stack on control cluster ───────────────────────────

log "Phase 3: Install CAPI stack on control cluster"
export KUBECONFIG="$CONTROL_KUBECONFIG"

echo "  Installing cert-manager on control cluster..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=120s

echo "  Installing CAPI Operator on control cluster..."
helm upgrade --install capi-operator capi-operator/cluster-api-operator \
  --create-namespace -n capi-operator-system --wait --timeout 5m

echo "  Creating AWS credentials secret on control cluster..."
"$REPO_ROOT/control/secrets/create-aws-secret.sh"

echo "  Applying CAPI providers on control cluster..."
kubectl apply -f "$REPO_ROOT/control/providers/namespaces.yml"
kubectl apply -f "$REPO_ROOT/control/providers/coreprovider-cluster-api.yml"
kubectl apply -f "$REPO_ROOT/control/providers/infrastructureprovider-aws.yml"
kubectl apply -f "$REPO_ROOT/control/providers/bootstrapprovider-rke2.yml"
kubectl apply -f "$REPO_ROOT/control/providers/controlplaneprovider-rke2.yml"

echo "  Waiting for providers on control cluster..."
sleep 30
wait_for "CoreProvider" bash -c "kubectl get coreproviders cluster-api -n capi-system -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
wait_for "InfrastructureProvider" bash -c "kubectl get infrastructureproviders aws -n aws-infrastructure-system -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
wait_for "BootstrapProvider" bash -c "kubectl get bootstrapproviders rke2 -n rke2-bootstrap-system -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"
wait_for "ControlPlaneProvider" bash -c "kubectl get controlplaneproviders rke2 -n rke2-control-plane-system -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' | grep -q True"

log "Phase 3 complete: CAPI ready on control cluster"

# ── Phase 4: Install ArgoCD on control cluster ──────────────────────────────

log "Phase 4: Install ArgoCD on control cluster"

"$REPO_ROOT/control/argocd/install.sh"

log "Phase 4 complete: ArgoCD running"

# ── Phase 5: Cleanup ────────────────────────────────────────────────────────

log "Bootstrap complete"
echo ""
echo "Control cluster kubeconfig: $CONTROL_KUBECONFIG"
echo "  kubectl --kubeconfig $CONTROL_KUBECONFIG get nodes"
echo ""
echo "ArgoCD admin password:"
echo "  kubectl --kubeconfig $CONTROL_KUBECONFIG -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
echo ""

unset KUBECONFIG
read -p "Delete bootstrap Kind cluster? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  kind delete cluster --name oasis-bootstrap
  echo "Bootstrap cluster deleted."
else
  echo "Bootstrap cluster kept. Delete later with: kind delete cluster --name oasis-bootstrap"
fi
