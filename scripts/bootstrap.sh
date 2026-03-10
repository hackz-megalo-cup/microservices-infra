#!/usr/bin/env bash
# Dev-fast bootstrap — kindnetd, single node, warm cluster support
# Usage: bootstrap [--clean] [--full]
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

platform_docker_desktop_check
HASH_DIR="${REPO_ROOT}/.bootstrap-state"
KIND_CONFIG="${REPO_ROOT}/k8s/kind-config-dev.yaml"

# ===========================================================================
# Argument parsing
# ===========================================================================
MODE="dev"
for arg in "$@"; do
  case "$arg" in
    --clean) MODE="clean" ;;
    --full)
      echo "Delegating to bootstrap-full.sh (Cilium mode)..."
      exec bash "${SCRIPT_DIR}/bootstrap-full.sh"
      ;;
  esac
done

# ===========================================================================
# Hash functions
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
# Step functions
# ===========================================================================
_step_kind_cluster() {
  if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    echo "Cluster '${CLUSTER_NAME}' already exists."
    kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
  else
    kind create cluster --config "${KIND_CONFIG}"
    kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
  fi
}

_step_image_preload() {
  echo "Pulling ${#PRELOAD_IMAGES_DEV[@]} images in parallel..."
  local pids=()
  for img in "${PRELOAD_IMAGES_DEV[@]}"; do
    docker pull "$img" &>/dev/null &
    pids+=($!)
  done
  local failed=0
  for i in "${!pids[@]}"; do
    if ! wait "${pids[$i]}"; then
      echo "WARNING: failed to pull ${PRELOAD_IMAGES_DEV[$i]}" >&2
      failed=1
    fi
  done
  if [[ "$failed" -ne 0 ]]; then
    echo "Some image pulls failed, continuing..."
  fi
}

_step_image_load() {
  echo "Loading images into kind cluster..."
  kind load docker-image "${PRELOAD_IMAGES_DEV[@]}" --name "${CLUSTER_NAME}" &>/dev/null &
  local bg_pid=$!

  # OTel image load
  bash "${SCRIPT_DIR}/load-otel-collector-image.sh" load

  wait "$bg_pid" 2>/dev/null || true
}

_step_postgresql_apply() {
  kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/postgresql/Namespace-database.yaml"
  kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/postgresql/ConfigMap-postgresql-init-scripts.yaml"
  kubectl apply -f "${REPO_ROOT}/manifests-result/postgresql/" --server-side --force-conflicts || true
}

_step_garage_deploy() {
  kubectl create namespace storage --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "${REPO_ROOT}/manifests-result/garage/" --server-side --force-conflicts
  echo "Waiting for Garage to be ready..."
  until kubectl get pod --no-headers -n storage -l app.kubernetes.io/name=garage 2>/dev/null | grep -q .; do
    sleep 2
  done
  kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=garage -n storage --timeout=120s
  echo "Running Garage setup..."
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

_step_traefik() {
  kubectl apply --server-side -f "${REPO_ROOT}/manifests-result/traefik/Namespace-edge.yaml"
  kubectl create namespace microservices --dry-run=client -o yaml | kubectl apply -f -
  for f in "${REPO_ROOT}/manifests-result/traefik/CustomResourceDefinition-"*.yaml; do
    kubectl apply --server-side --force-conflicts -f "$f"
  done
  kubectl apply -f "${REPO_ROOT}/manifests-result/traefik/" --server-side --force-conflicts
  kubectl apply --server-side -f "${REPO_ROOT}/patches/traefik-auth.yaml"
}

_step_redpanda_deploy() {
  if [[ -d "${REPO_ROOT}/manifests-result/redpanda/" ]]; then
    kubectl create namespace messaging --dry-run=client -o yaml | kubectl apply -f -
    kubectl apply -f "${REPO_ROOT}/manifests-result/redpanda/" --server-side --force-conflicts || true
  else
    echo "Skipping Redpanda: manifests not generated yet"
  fi
}

_step_cloudflared() {
  if kubectl get secret tunnel-credentials -n cloudflare &>/dev/null; then
    kubectl apply -f "${REPO_ROOT}/manifests-result/cloudflared/" --server-side
  else
    echo "Skipping: run 'cloudflared-setup' first to create tunnel credentials"
  fi
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
# Bootstrap paths
# ===========================================================================
_cold_start() {
  timing_init "bootstrap-dev"

  # --- Phase 1: Preparation (parallel) ---
  export -f _step_kind_cluster _step_image_preload
  export CLUSTER_NAME KIND_CONFIG SCRIPT_DIR REPO_ROOT PRELOAD_IMAGES_DEV
  timed_step "phase1-prep" parallel_run \
    "kind-cluster:_step_kind_cluster" \
    "gen-manifests:bash ${SCRIPT_DIR}/gen-manifests.sh" \
    "otel-fetch:bash ${SCRIPT_DIR}/load-otel-collector-image.sh smart" \
    "image-preload:_step_image_preload"

  # --- Phase 2: Image load (no Cilium install!) ---
  timed_step "phase2-load" _step_image_load

  # --- Phase 2.5: PostgreSQL early start ---
  _step_postgresql_apply

  # --- Phase 3: Deploy services (parallel) ---
  export -f _step_garage_deploy _step_observability _step_traefik _step_cloudflared _step_redpanda_deploy
  timed_step "phase3-deploy" parallel_run \
    "garage:_step_garage_deploy" \
    "observability:_step_observability" \
    "traefik:_step_traefik" \
    "redpanda:_step_redpanda_deploy" \
    "cloudflared:_step_cloudflared"

  # --- Phase 4: Wait for all pods (parallel) ---
  timed_step "phase4-wait" _step_wait_all

  _save_hashes
  timing_report
}

_warm_reapply() {
  echo "=== Warm reapply: manifests changed ==="
  bash "${SCRIPT_DIR}/gen-manifests.sh"

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
  exit 0
fi

# Warm cluster logic
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

echo ""
echo "=== Bootstrap complete (dev-fast) ==="
echo "Mode: kindnetd (no Cilium)"
echo "Node: single control-plane"
echo ""
echo "Next: cd microservice-app && tilt up"
echo ""
echo "  Grafana:      http://localhost:30300  (admin/admin)"
echo "  Prometheus:   http://localhost:30090"
echo "  Alertmanager: http://localhost:30093"
echo "  Traefik:      http://localhost:30081"
echo "  Redpanda:     http://localhost:30082"
echo ""
echo "Options:"
echo "  bootstrap --clean  : Force full rebuild"
echo "  bootstrap --full   : Use Cilium (parity mode)"
