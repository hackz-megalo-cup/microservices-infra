#!/usr/bin/env bash
# Lightweight bootstrap — Istio なし、ArgoCD なし、worker 1台
# full-bootstrap.sh のメモリ削減版
# アプリのデプロイは tilt up で行う
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

CLUSTER_NAME="microservice-infra"

# --- Step 1: Kind cluster (lite config: worker 1台) ---
echo "=== Step 1: Creating kind cluster (lite: 1 worker) ==="
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists."
  kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
else
  kind create cluster --config "${REPO_ROOT}/k8s/kind-config-lite.yaml"
  kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
fi

echo ""
echo "=== Step 1.1: Installing Cilium CNI ==="
bash "${SCRIPT_DIR}/cilium-install.sh"

# Istio・ArgoCD は省略 — ローカル開発では不要

echo ""
echo "=== Step 2: Generating manifests ==="
bash "${SCRIPT_DIR}/gen-manifests.sh"

echo ""
echo "=== Step 3: Loading OTel Collector image ==="
bash "${SCRIPT_DIR}/load-otel-collector-image.sh"

echo ""
echo "=== Step 3.5: Deploying Garage object storage ==="
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
echo "=== Step 4: Deploying Observability stack ==="
kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/kube-prometheus-stack/Namespace-observability.yaml"

for f in "${REPO_ROOT}/manifests-result/kube-prometheus-stack/CustomResourceDefinition-"*.yaml; do
  kubectl apply --server-side --force-conflicts -f "$f"
done

kubectl apply -f "${REPO_ROOT}/manifests-result/kube-prometheus-stack/" --server-side --force-conflicts
kubectl apply -f "${REPO_ROOT}/manifests-result/loki/" --server-side --force-conflicts
kubectl apply -f "${REPO_ROOT}/manifests-result/tempo/" --server-side --force-conflicts
kubectl apply -f "${REPO_ROOT}/manifests-result/otel-collector/" --server-side --force-conflicts

echo ""
echo "=== Step 4.5: Deploying Cloudflare Tunnel ==="
if kubectl get secret tunnel-credentials -n cloudflare &>/dev/null; then
  kubectl apply -f "${REPO_ROOT}/manifests-result/cloudflared/" --server-side
else
  echo "Skipping: run 'cloudflared-setup' first to create tunnel credentials"
fi

echo ""
echo "=== Step 4.7: Deploying PostgreSQL ==="
kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/postgresql/Namespace-database.yaml"
kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/postgresql/ConfigMap-postgresql-init-scripts.yaml"
kubectl apply -f "${REPO_ROOT}/manifests-result/postgresql/" --server-side --force-conflicts || true
echo "Waiting for PostgreSQL to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n database --timeout=180s

echo ""
echo "=== Step 5: Deploying Traefik ==="
# Namespace と CRD を先に適用
kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/traefik/Namespace-edge.yaml"
kubectl create namespace microservices --dry-run=client -o yaml | kubectl apply -f -
for f in "${REPO_ROOT}/manifests-result/traefik/CustomResourceDefinition-"*.yaml; do
  kubectl apply --server-side --force-conflicts -f "$f"
done
kubectl apply -f "${REPO_ROOT}/manifests-result/traefik/" --server-side --force-conflicts

echo ""
echo "=== Step 5.1: Applying Traefik auth patch (replaces Istio JWT) ==="
kubectl apply --server-side -f "${REPO_ROOT}/patches/traefik-auth.yaml"

echo ""
echo "=== Step 6: Waiting for pods ==="
echo "Waiting for observability pods to be created..."
for label in "app.kubernetes.io/name=grafana" "app.kubernetes.io/name=prometheus"; do
  until kubectl get pod -n observability -l "$label" 2>/dev/null | grep -q .; do
    sleep 2
  done
  kubectl wait --for=condition=ready pod -l "$label" -n observability --timeout=300s
done

echo ""
echo "=== Bootstrap complete (lite) ==="
echo "Skipped: Istio, ArgoCD"
echo "Workers: 1 (reduced from 2)"
echo ""
echo "Next: cd microservice-app && tilt up"
echo ""
echo "  Grafana:      http://localhost:30300  (admin/admin)"
echo "  Prometheus:   http://localhost:30090"
echo "  Alertmanager: http://localhost:30093"
echo "  Hubble UI:    http://localhost:31235"
echo "  Traefik:      http://localhost:30081"
