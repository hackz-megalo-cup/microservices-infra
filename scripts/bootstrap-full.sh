#!/usr/bin/env bash
# Lightweight bootstrap — Istio なし、ArgoCD なし、worker 1台
# full-bootstrap.sh のメモリ削減版
# アプリのデプロイは tilt up で行う
set -euo pipefail
trap 'jobs -p | xargs -r kill 2>/dev/null; wait 2>/dev/null' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

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
    kind create cluster --config "${REPO_ROOT}/k8s/kind-config-lite.yaml"
    kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
  fi
}

_step_image_preload() {
  echo "Pulling ${#PRELOAD_IMAGES[@]} images in parallel..."
  local pids=()
  for img in "${PRELOAD_IMAGES[@]}"; do
    docker pull "$img" &>/dev/null &
    pids+=($!)
  done
  local failed=0
  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      echo "WARNING: failed to pull ${PRELOAD_IMAGES[$i]}" >&2
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
  if ! kind load docker-image "quay.io/cilium/cilium:v${CILIUM_VERSION}" --name "${CLUSTER_NAME}" 2>/dev/null; then
    echo "WARNING: Failed to load Cilium image into kind" >&2
  fi
  bash "${SCRIPT_DIR}/load-otel-collector-image.sh" load

  # 2. Start loading remaining images in background (overlaps with cilium install)
  echo "Loading remaining images into kind cluster (background, during cilium install)..."
  kind load docker-image "${PRELOAD_IMAGES[@]}" --name "${CLUSTER_NAME}" &>/dev/null &
  _BG_IMAGE_LOAD_PID=$!

  # 3. Install Cilium (runs while remaining images load in background)
  echo "Installing Cilium..."
  bash "${SCRIPT_DIR}/cilium-install.sh"

  # 4. Wait for background image load to finish before Phase 3
  echo "Waiting for image load to complete..."
  wait "$_BG_IMAGE_LOAD_PID" 2>/dev/null || true
  _BG_IMAGE_LOAD_PID=""

  # 5. Start PostgreSQL early (longest pod startup, ~87s)
  echo "Starting PostgreSQL early..."
  _step_postgresql_apply
}

_step_garage_deploy() {
  kubectl create namespace storage --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "${REPO_ROOT}/manifests-result/garage/" --server-side --force-conflicts
  echo "Waiting for Garage to be ready..."
  until kubectl get pod --no-headers -n storage -l app.kubernetes.io/name=garage 2>/dev/null | grep -q .; do
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

  # Wait for CRDs to be established before applying CRs (Prometheus, Alertmanager, etc.)
  if kubectl get crd prometheuses.monitoring.coreos.com &>/dev/null; then
    kubectl wait --for=condition=established crd prometheuses.monitoring.coreos.com --timeout=60s
  else
    echo "WARNING: CRD prometheuses.monitoring.coreos.com not found, skipping wait" >&2
  fi
  if kubectl get crd alertmanagers.monitoring.coreos.com &>/dev/null; then
    kubectl wait --for=condition=established crd alertmanagers.monitoring.coreos.com --timeout=60s
  else
    echo "WARNING: CRD alertmanagers.monitoring.coreos.com not found, skipping wait" >&2
  fi

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

_step_traefik() {
  # Namespace と CRD を先に適用
  kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/traefik/Namespace-edge.yaml"
  kubectl create namespace microservices --dry-run=client -o yaml | kubectl apply -f -
  for f in "${REPO_ROOT}/manifests-result/traefik/CustomResourceDefinition-"*.yaml; do
    kubectl apply --server-side --force-conflicts -f "$f"
  done
  kubectl apply -f "${REPO_ROOT}/manifests-result/traefik/" --server-side --force-conflicts

  # Traefik auth patch (replaces Istio JWT)
  kubectl apply --server-side -f "${REPO_ROOT}/patches/traefik-auth.yaml"
}

_wait_for_pod() {
  local label="$1" namespace="$2" timeout="${3:-300}"
  local max_poll=120 waited=0
  until kubectl get pod --no-headers -n "$namespace" -l "$label" 2>/dev/null | grep -q .; do
    sleep 2
    waited=$((waited + 2))
    if [[ $waited -ge $max_poll ]]; then
      echo "WARNING: pod with label '$label' not found in $namespace after ${max_poll}s, skipping"
      return 0
    fi
  done
  kubectl wait --for=condition=ready pod -l "$label" -n "$namespace" --timeout="${timeout}s"
}

_step_wait_all() {
  echo "Waiting for pods (parallel)..."

  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=postgresql -n database --timeout=180s &
  local pid_pg=$!

  _wait_for_pod "app.kubernetes.io/name=grafana" "observability" 300 &
  local pid_gr=$!

  _wait_for_pod "app.kubernetes.io/name=prometheus" "observability" 300 &
  local pid_pr=$!

  local failed=0
  wait $pid_pg || failed=1
  wait $pid_gr || failed=1
  wait $pid_pr || failed=1

  if [[ "$failed" -ne 0 ]]; then
    echo "ERROR: Some pods failed to become ready" >&2
    return 1
  fi
}

# ===========================================================================
# Main — 4-phase parallel execution
# ===========================================================================

timing_init "bootstrap"

# --- Phase 1: Preparation (parallel) ---
# kind-cluster, gen-manifests, otel-build, image-preload run concurrently
export -f _step_kind_cluster _step_image_preload
export CLUSTER_NAME SCRIPT_DIR REPO_ROOT PRELOAD_IMAGES
timed_step "phase1-prep" parallel_run \
  "kind-cluster:_step_kind_cluster" \
  "gen-manifests:bash ${SCRIPT_DIR}/gen-manifests.sh" \
  "otel-build:bash ${SCRIPT_DIR}/load-otel-collector-image.sh build" \
  "image-preload:_step_image_preload"

# --- Phase 2: Network setup (sequential) ---
# Load images into kind + install Cilium (requires kind cluster from Phase 1)
timed_step "phase2-network" _step_network_setup

# --- Phase 3: Deploy services (parallel) ---
# garage, observability, traefik, cloudflared run concurrently
# (postgresql already started at end of Phase 2 for maximum startup overlap)
export -f _step_garage_deploy _step_observability _step_traefik _step_cloudflared
timed_step "phase3-deploy" parallel_run \
  "garage:_step_garage_deploy" \
  "observability:_step_observability" \
  "traefik:_step_traefik" \
  "cloudflared:_step_cloudflared"


# --- Phase 4: Wait for all pods ---
timed_step "phase4-wait" _step_wait_all

timing_report

# Istio・ArgoCD は省略 — ローカル開発では不要

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
