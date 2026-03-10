#!/usr/bin/env bash
# Full bootstrap — Istio + ArgoCD + 2 workers
# 4-phase parallel execution for maximum speed
# Usage: full-bootstrap [--clean]
set -euo pipefail
trap 'jobs -p | xargs -r kill 2>/dev/null; wait 2>/dev/null' EXIT

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
KIND_CONFIG="${REPO_ROOT}/k8s/kind-config.yaml"
HASH_DIR="${REPO_ROOT}/.bootstrap-state-full"
_BG_IMAGE_LOAD_PID=""

# ===========================================================================
# Argument parsing
# ===========================================================================
MODE="default"
for arg in "$@"; do
  case "$arg" in
    --clean) MODE="clean" ;;
  esac
done

# ===========================================================================
# Hash functions (warm cluster support)
# ===========================================================================
_compute_cluster_hash() {
  cat "${KIND_CONFIG}" "${SCRIPT_DIR}/lib/images.sh" \
    | shasum -a 256 | cut -d' ' -f1
}

_compute_manifest_hash() {
  if [[ -d "${REPO_ROOT}/manifests-result" ]]; then
    find "${REPO_ROOT}/manifests-result" -type f -print0 | sort -z | xargs -0 cat \
      | shasum -a 256 | cut -d' ' -f1
  else
    echo "no-manifests"
  fi
}

_cluster_healthy() {
  kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$" || return 1
  kubectl cluster-info --context "kind-${CLUSTER_NAME}" &>/dev/null || return 1
  kubectl get nodes --no-headers 2>/dev/null | grep -q " Ready" || return 1
  return 0
}

_save_hashes() {
  mkdir -p "$HASH_DIR"
  _compute_cluster_hash > "${HASH_DIR}/cluster"
  _compute_manifest_hash > "${HASH_DIR}/manifest"
}

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
  if ! kind load docker-image "quay.io/cilium/cilium:v${CILIUM_VERSION}" --name "${CLUSTER_NAME}" 2>/dev/null; then
    echo "WARNING: Failed to load Cilium image into kind" >&2
  fi
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
  for attempt in 1 2 3; do
    if kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml; then
      break
    fi
    echo "Gateway API CRDs apply failed (attempt $attempt/3), retrying in 5s..."
    [[ $attempt -lt 3 ]] && sleep 5
  done

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

_step_traefik() {
  kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/traefik/Namespace-edge.yaml"
  # Apply CRDs first (skip Gateway API CRDs to avoid conflict with v1.5.0 installed in Step 1.6)
  for f in "${REPO_ROOT}/manifests-result/traefik/CustomResourceDefinition-"*.yaml; do
    if ! grep -q "gateway.networking.k8s.io" "$f"; then
      kubectl apply --server-side --force-conflicts -f "$f"
    fi
  done
  # Apply all traefik components (skip Gateway API CRD manifests)
  for f in "${REPO_ROOT}/manifests-result/traefik/"*.yaml; do
    if ! grep -q "gateway.networking.k8s.io" "$f"; then
      kubectl apply --server-side --force-conflicts -f "$f"
    fi
  done
  echo "Waiting for Traefik to be ready..."
  until kubectl get pod -n edge -l app.kubernetes.io/name=traefik 2>/dev/null | grep -q .; do
    sleep 2
  done
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=traefik -n edge --timeout=120s
}

_step_postgresql_apply() {
  kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/postgresql/Namespace-database.yaml"
  kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/postgresql/ConfigMap-postgresql-init-scripts.yaml"
  kubectl apply -f "${REPO_ROOT}/manifests-result/postgresql/" --server-side --force-conflicts || true
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

  kubectl wait --for=condition=available deployment/argocd-server \
    -n argocd --timeout=300s &
  local pid_argo=$!

  kubectl wait --for=condition=ready pod \
    -l app.kubernetes.io/name=postgresql -n database --timeout=180s &
  local pid_pg=$!

  _wait_for_pod "app.kubernetes.io/name=grafana" "observability" 300 &
  local pid_gr=$!

  _wait_for_pod "app.kubernetes.io/name=prometheus" "observability" 300 &
  local pid_pr=$!

  local failed=0
  wait $pid_argo || failed=1
  wait $pid_pg || failed=1
  wait $pid_gr || failed=1
  wait $pid_pr || failed=1

  if [[ "$failed" -ne 0 ]]; then
    echo "ERROR: Some pods failed to become ready" >&2
    return 1
  fi
}

# ===========================================================================
# Bootstrap paths
# ===========================================================================
_cold_start() {
  timing_init "full-bootstrap"

  # --- Phase 1: Preparation (parallel) ---
  export -f _step_kind_cluster _step_image_preload
  export CLUSTER_NAME KIND_CONFIG SCRIPT_DIR REPO_ROOT PRELOAD_IMAGES_FULL
  timed_step "phase1-prep" parallel_run \
    "kind-cluster:_step_kind_cluster" \
    "gen-manifests:bash ${SCRIPT_DIR}/gen-manifests.sh" \
    "otel-build:bash ${SCRIPT_DIR}/load-otel-collector-image.sh build" \
    "image-preload:_step_image_preload"

  # --- Phase 2: Network setup (sequential) ---
  timed_step "phase2-network" _step_network_setup

  # --- Phase 3: Deploy services (parallel) ---
  export -f _step_argocd_apply _step_garage_deploy _step_observability _step_cloudflared _step_traefik
  timed_step "phase3-deploy" parallel_run \
    "argocd-apply:_step_argocd_apply" \
    "garage:_step_garage_deploy" \
    "observability:_step_observability" \
    "cloudflared:_step_cloudflared" \
    "traefik:_step_traefik"

  # --- Phase 4: Wait for all pods (parallel) ---
  timed_step "phase4-wait" _step_wait_all

  _save_hashes
  timing_report
}

_warm_reapply() {
  echo "=== Warm reapply: manifests changed ==="
  bash "${SCRIPT_DIR}/gen-manifests.sh"

  _step_argocd_apply
  _step_observability
  _step_traefik
  _step_postgresql_apply
  _step_cloudflared
  _step_wait_all

  _save_hashes
  echo "=== Warm reapply complete ==="
}

_warm_verify() {
  echo "=== Cluster up-to-date. Quick health check ==="
  kubectl get pods -A --no-headers | head -20
  echo "=== All good ==="
}

# ===========================================================================
# Main
# ===========================================================================
if [[ "$MODE" == "clean" ]]; then
  echo "Clean mode: destroying existing cluster..."
  kind delete cluster --name "${CLUSTER_NAME}" 2>/dev/null || true
  rm -rf "$HASH_DIR"
  _cold_start
else
  cluster_hash="$(_compute_cluster_hash)"
  stored_cluster_hash=""
  stored_manifest_hash=""
  [[ -f "${HASH_DIR}/cluster" ]] && stored_cluster_hash="$(cat "${HASH_DIR}/cluster")"
  [[ -f "${HASH_DIR}/manifest" ]] && stored_manifest_hash="$(cat "${HASH_DIR}/manifest")"

  if _cluster_healthy; then
    if [[ "$cluster_hash" != "$stored_cluster_hash" ]]; then
      echo "Cluster config changed. Full rebuild."
      kind delete cluster --name "${CLUSTER_NAME}"
      rm -rf "$HASH_DIR"
      _cold_start
    else
      manifest_hash="$(_compute_manifest_hash)"
      if [[ "$manifest_hash" != "$stored_manifest_hash" ]]; then
        _warm_reapply
      else
        _warm_verify
      fi
    fi
  else
    _cold_start
  fi
fi

ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || echo "<not found>")

echo ""
echo "=== Bootstrap complete (full) ==="
echo "ArgoCD will sync the remaining applications automatically."
echo ""
echo "  ArgoCD:       http://localhost:30080  (admin/${ARGOCD_PASS})"
echo "  Grafana:      http://localhost:30300  (admin/admin)"
echo "  Prometheus:   http://localhost:30090"
echo "  Alertmanager: http://localhost:30093"
echo "  Hubble UI:    http://localhost:31235"
echo "  Traefik:      http://localhost:30081"
echo ""
echo "Options:"
echo "  full-bootstrap --clean  : Force full rebuild"
