#!/usr/bin/env bash
# Full bootstrap — Istio + ArgoCD + 2 workers
# 4-phase parallel execution for maximum speed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Load shared libraries
# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"
# shellcheck source=lib/timing.sh
source "${SCRIPT_DIR}/lib/timing.sh"
# shellcheck source=lib/monitor.sh
source "${SCRIPT_DIR}/lib/monitor.sh"
# shellcheck source=lib/parallel.sh
source "${SCRIPT_DIR}/lib/parallel.sh"
# shellcheck source=lib/images.sh
source "${SCRIPT_DIR}/lib/images.sh"

CLUSTER_NAME="microservice-infra"
_BG_IMAGE_LOAD_PID=""

# ===========================================================================
# Helper functions (one per timed_step)
# ===========================================================================

_step_kind_cluster() {
  if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster '${CLUSTER_NAME}' already exists."
    kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
  else
    kind create cluster --config "${REPO_ROOT}/k8s/kind-config.yaml"
    kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
  fi
}

_step_image_preload() {
  echo "Pulling ${#PRELOAD_IMAGES_FULL[@]} images in parallel..."
  local pids=()
  for img in "${PRELOAD_IMAGES_FULL[@]}"; do
    docker pull "$img" &>/dev/null &
    pids+=($!)
  done
  local failed=0
  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      echo "WARNING: failed to pull ${PRELOAD_IMAGES_FULL[$i]}" >&2
      failed=1
    fi
  done
  if [[ "$failed" -ne 0 ]]; then
    echo "Some image pulls failed, continuing with available images..."
  fi
  echo "Image preload (pull) complete."
}

_step_network_setup() {
  # 1. Load cilium + otel images into kind
  echo "Loading Cilium image into kind cluster..."
  kind load docker-image "quay.io/cilium/cilium:v${CILIUM_VERSION}" --name "${CLUSTER_NAME}" 2>/dev/null || true
  bash "${SCRIPT_DIR}/load-otel-collector-image.sh" load

  # 2. Start loading remaining images in background (overlaps with cilium/istio install)
  echo "Loading remaining images into kind cluster (background, during network install)..."
  kind load docker-image "${PRELOAD_IMAGES_FULL[@]}" --name "${CLUSTER_NAME}" &>/dev/null &
  _BG_IMAGE_LOAD_PID=$!

  # 3. Install Cilium (runs while remaining images load in background)
  echo "Installing Cilium..."
  bash "${SCRIPT_DIR}/cilium-install.sh"

  # 4. Install Istio
  echo "Installing Istio..."
  bash "${SCRIPT_DIR}/istio-install.sh"

  # 5. Apply Gateway API CRDs
  echo "Applying Gateway API CRDs..."
  kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

  # 6. Wait for background image load to finish before Phase 3
  echo "Waiting for image load to complete..."
  wait "$_BG_IMAGE_LOAD_PID" 2>/dev/null || true
  _BG_IMAGE_LOAD_PID=""

  # 7. Start PostgreSQL early (longest pod startup, ~87s)
  echo "Starting PostgreSQL early..."
  _step_postgresql_apply
}

_step_argocd_apply() {
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "${REPO_ROOT}/manifests-result/argocd/" --server-side --force-conflicts
}

_step_garage_deploy() {
  kubectl create namespace storage --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "${REPO_ROOT}/manifests-result/garage/" --server-side --force-conflicts
  echo "Waiting for Garage to be ready..."
  until kubectl get pod -n storage -l app.kubernetes.io/name=garage 2>/dev/null | grep -q .; do
    sleep 2
  done
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=garage -n storage --timeout=120s
  echo "Running Garage setup (layout + buckets + secrets)..."
  bash "${SCRIPT_DIR}/garage-setup.sh"
}

_step_observability() {
  kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/kube-prometheus-stack/Namespace-observability.yaml"

  for f in "${REPO_ROOT}/manifests-result/kube-prometheus-stack/CustomResourceDefinition-"*.yaml; do
    kubectl apply --server-side --force-conflicts -f "$f"
  done

  kubectl apply -f "${REPO_ROOT}/manifests-result/kube-prometheus-stack/" --server-side --force-conflicts
  kubectl apply -f "${REPO_ROOT}/manifests-result/loki/" --server-side --force-conflicts
  kubectl apply -f "${REPO_ROOT}/manifests-result/tempo/" --server-side --force-conflicts
  kubectl apply -f "${REPO_ROOT}/manifests-result/otel-collector/" --server-side --force-conflicts
}

_step_cloudflared() {
  if kubectl get secret tunnel-credentials -n cloudflare &>/dev/null; then
    kubectl apply -f "${REPO_ROOT}/manifests-result/cloudflared/" --server-side
  else
    echo "Skipping: run 'cloudflared-setup' first to create tunnel credentials"
  fi
}

_step_postgresql_apply() {
  kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/postgresql/Namespace-database.yaml"
  kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/postgresql/ConfigMap-postgresql-init-scripts.yaml"
  kubectl apply -f "${REPO_ROOT}/manifests-result/postgresql/" --server-side --force-conflicts || true
}

_step_wait_all() {
  # Wait for ArgoCD server
  echo "Waiting for ArgoCD server to be ready..."
  kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

  # Wait for PostgreSQL
  echo "Waiting for PostgreSQL to be ready..."
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql -n database --timeout=180s

  # Wait for observability pods (grafana + prometheus)
  echo "Waiting for observability pods to be created..."
  for label in "app.kubernetes.io/name=grafana" "app.kubernetes.io/name=prometheus"; do
    until kubectl get pod -n observability -l "$label" 2>/dev/null | grep -q .; do
      sleep 2
    done
    kubectl wait --for=condition=ready pod -l "$label" -n observability --timeout=300s
  done
}

# ===========================================================================
# Main — 4-phase parallel execution
# ===========================================================================

timing_init "full-bootstrap"

# --- Phase 1: Preparation (parallel) ---
# kind-cluster, gen-manifests, otel-build, image-preload run concurrently
export -f _step_kind_cluster _step_image_preload
export CLUSTER_NAME SCRIPT_DIR REPO_ROOT PRELOAD_IMAGES_FULL
timed_step "phase1-prep" parallel_run \
  "kind-cluster:_step_kind_cluster" \
  "gen-manifests:bash ${SCRIPT_DIR}/gen-manifests.sh" \
  "otel-build:bash ${SCRIPT_DIR}/load-otel-collector-image.sh build" \
  "image-preload:_step_image_preload"

# --- Phase 2: Network setup (sequential) ---
# Load images into kind + install Cilium + Istio + Gateway API CRDs
# (requires kind cluster from Phase 1)
timed_step "phase2-network" _step_network_setup

# --- Phase 3: Deploy services (parallel) ---
# argocd, garage, observability, cloudflared run concurrently
# (postgresql already started at end of Phase 2 for maximum startup overlap)
export -f _step_argocd_apply _step_garage_deploy _step_observability _step_cloudflared
timed_step "phase3-deploy" parallel_run \
  "argocd-apply:_step_argocd_apply" \
  "garage:_step_garage_deploy" \
  "observability:_step_observability" \
  "cloudflared:_step_cloudflared"


# --- Phase 4: Wait for all pods ---
timed_step "phase4-wait" _step_wait_all

timing_report

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
