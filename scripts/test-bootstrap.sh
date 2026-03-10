#!/usr/bin/env bash
# scripts/test-bootstrap.sh — Automated bootstrap test cycle
# Deletes existing cluster, runs bootstrap, verifies all pods are healthy.
# Usage: test-bootstrap.sh [bootstrap|full-bootstrap]
set -euo pipefail
trap 'jobs -p | xargs -r kill 2>/dev/null; wait 2>/dev/null' EXIT

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
export REPO_ROOT

# ---------------------------------------------------------------------------
# Source shared libraries
# ---------------------------------------------------------------------------
# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"
# shellcheck source=lib/timing.sh
source "${SCRIPT_DIR}/lib/timing.sh"

CLUSTER_NAME="microservice-infra"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [MODE] [OPTIONS]

Automated bootstrap test cycle — clean cluster, bootstrap, verify pods.

Arguments:
  MODE   Bootstrap mode: "bootstrap" or "full-bootstrap" (default: bootstrap)

Options:
  --help   Show this help message

Examples:
  $(basename "$0")                  # Test bootstrap.sh (dev-fast)
  $(basename "$0") full-bootstrap   # Test full-bootstrap.sh (Cilium mode)
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
MODE="bootstrap"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      ;;
    bootstrap|full-bootstrap)
      MODE="$1"
      shift
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      echo "Run '$(basename "$0") --help' for usage." >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Map mode to script path
# ---------------------------------------------------------------------------
case "$MODE" in
  bootstrap)
    BOOTSTRAP_SCRIPT="${SCRIPT_DIR}/bootstrap.sh"
    ;;
  full-bootstrap)
    BOOTSTRAP_SCRIPT="${SCRIPT_DIR}/full-bootstrap.sh"
    ;;
  *)
    echo "Error: unknown mode '$MODE'" >&2
    exit 1
    ;;
esac

if [[ ! -f "$BOOTSTRAP_SCRIPT" ]]; then
  echo "Error: script not found: $BOOTSTRAP_SCRIPT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
preflight_ok="true"

if ! command -v docker &>/dev/null; then
  echo "Error: docker is not installed or not in PATH" >&2
  preflight_ok="false"
fi

if ! command -v kind &>/dev/null; then
  echo "Error: kind is not installed or not in PATH" >&2
  preflight_ok="false"
fi

if ! command -v kubectl &>/dev/null; then
  echo "Error: kubectl is not installed or not in PATH" >&2
  preflight_ok="false"
fi

if command -v docker &>/dev/null && ! docker info &>/dev/null; then
  echo "Error: Docker daemon is not running" >&2
  preflight_ok="false"
fi

if [[ "$preflight_ok" != "true" ]]; then
  echo "" >&2
  echo "Pre-flight checks failed. Aborting." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Main test cycle
# ---------------------------------------------------------------------------
timing_init "test-bootstrap-${MODE}"

# --- Phase 1: Delete existing cluster ---
timed_step "delete-cluster" bash -c "
  echo 'Deleting existing kind cluster (${CLUSTER_NAME})...'
  kind delete cluster --name '${CLUSTER_NAME}' 2>/dev/null || true
  echo 'Cluster deleted (or did not exist).'
"

# --- Phase 2: Run bootstrap ---
timed_step "run-bootstrap" bash "$BOOTSTRAP_SCRIPT" --clean

# --- Phase 3: Verify pods ---
echo ""
echo "=== Pod Verification ==="
echo ""

kubectl get pods -A
echo ""

# Check pod statuses: every pod should be Running or Completed (Succeeded)
_verify_pods() {
  local bad_pods
  bad_pods="$(kubectl get pods -A --no-headers 2>/dev/null \
    | awk '{print $4}' \
    | grep -v -E '^(Running|Completed|Succeeded)$' || true)"

  if [[ -z "$bad_pods" ]]; then
    echo "All pods are Running or Completed."
    return 0
  else
    echo "ERROR: Some pods are not healthy:" >&2
    kubectl get pods -A --no-headers 2>/dev/null \
      | awk '$4 !~ /^(Running|Completed|Succeeded)$/ {print "  " $0}' >&2
    return 1
  fi
}

timed_step "verify-pods" _verify_pods

# --- Timing report ---
timing_report

echo ""
echo "=== Test Bootstrap: PASSED ==="
echo "Mode: ${MODE}"
echo ""
