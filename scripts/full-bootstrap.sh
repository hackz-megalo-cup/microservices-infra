#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Step 1: Creating kind cluster (+ Cilium CNI) ==="
bash "${SCRIPT_DIR}/cluster-up.sh"

echo ""
echo "=== Step 1.5: Installing Istio (ambient mode) ==="
bash "${SCRIPT_DIR}/istio-install.sh"

echo ""
echo "=== Step 1.6: Installing Gateway API CRDs (v1.5.0) ==="
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

echo ""
echo "=== Step 2: Generating manifests ==="
bash "${SCRIPT_DIR}/gen-manifests.sh"

echo ""
echo "=== Step 3: Bootstrapping ArgoCD ==="
bash "${SCRIPT_DIR}/argocd-bootstrap.sh"

echo ""
echo "=== Step 4: Loading OTel Collector image ==="
bash "${SCRIPT_DIR}/load-otel-collector-image.sh"

echo ""
echo "=== Step 4.5: Deploying Garage object storage ==="
kubectl create namespace storage --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "${REPO_ROOT}/manifests-result/garage/" --server-side --force-conflicts
echo "Waiting for Garage to be ready..."
until kubectl get pod -n storage -l app.kubernetes.io/name=garage 2>/dev/null | grep -q .; do
  sleep 2
done
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=garage -n storage --timeout=120s
echo "Running Garage setup (layout + buckets + secrets)..."
bash "${SCRIPT_DIR}/garage-setup.sh"

echo ""
echo "=== Step 5: Deploying Observability stack ==="
# Create namespace first (other resources reference it)
kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/kube-prometheus-stack/Namespace-observability.yaml"

# Apply CRDs (required before CRs like ServiceMonitor, PrometheusRule)
for f in "${REPO_ROOT}/manifests-result/kube-prometheus-stack/CustomResourceDefinition-"*.yaml; do
  kubectl apply --server-side --force-conflicts -f "$f"
done

# Apply all components
kubectl apply -f "${REPO_ROOT}/manifests-result/kube-prometheus-stack/" --server-side --force-conflicts
kubectl apply -f "${REPO_ROOT}/manifests-result/loki/" --server-side --force-conflicts
kubectl apply -f "${REPO_ROOT}/manifests-result/tempo/" --server-side --force-conflicts
kubectl apply -f "${REPO_ROOT}/manifests-result/otel-collector/" --server-side --force-conflicts

echo ""
echo "=== Step 5.5: Deploying Cloudflare Tunnel ==="
if kubectl get secret tunnel-credentials -n cloudflare &>/dev/null; then
  kubectl apply -f "${REPO_ROOT}/manifests-result/cloudflared/" --server-side
else
  echo "Skipping: run 'cloudflared-setup' first to create tunnel credentials"
fi

echo ""
echo "=== Step 5.7: Deploying PostgreSQL ==="
kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/postgresql/Namespace-database.yaml"
kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/postgresql/ConfigMap-postgresql-init-scripts.yaml"
kubectl apply -f "${REPO_ROOT}/manifests-result/postgresql/" --server-side --force-conflicts || true
echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n database --timeout=180s

echo ""
echo "=== Step 6: Waiting for pods ==="
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

# Operator-managed pods (Grafana, Prometheus) may not exist immediately after apply.
# Poll until the pods appear, then wait for readiness.
echo "Waiting for observability pods to be created..."
for label in "app.kubernetes.io/name=grafana" "app.kubernetes.io/name=prometheus"; do
  until kubectl get pod -n observability -l "$label" 2>/dev/null | grep -q .; do
    sleep 2
  done
  kubectl wait --for=condition=ready pod -l "$label" -n observability --timeout=300s
done

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "<not found>")

echo ""
echo "=== Bootstrap complete ==="
echo "ArgoCD will sync the remaining applications automatically."
echo ""
echo "  ArgoCD:       http://localhost:30080  (admin/${ARGOCD_PASS})"
echo "  Grafana:      http://localhost:30300  (admin/admin)"
echo "  Prometheus:   http://localhost:30090"
echo "  Alertmanager: http://localhost:30093"
echo "  Hubble UI:    http://localhost:31235"
echo "  Traefik:      http://localhost:30081"
