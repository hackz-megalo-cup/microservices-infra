#!/usr/bin/env bash
# scripts/benchmark.sh — Benchmark runner for bootstrap scripts
# Usage: benchmark.sh [bootstrap|full-bootstrap] [runs] [--keep-logs]
set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
export REPO_ROOT

# ---------------------------------------------------------------------------
# Source platform detection
# ---------------------------------------------------------------------------
# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [MODE] [RUNS] [OPTIONS]

Benchmark runner for bootstrap scripts.

Arguments:
  MODE        Bootstrap mode: "bootstrap" or "full-bootstrap" (default: bootstrap)
  RUNS        Number of benchmark runs (default: 3)

Options:
  --keep-logs  Keep previous benchmark logs instead of cleaning them
  --help       Show this help message

Examples:
  $(basename "$0")                          # 3 runs of bootstrap.sh
  $(basename "$0") full-bootstrap 5         # 5 runs of full-bootstrap.sh
  $(basename "$0") bootstrap 3 --keep-logs  # keep previous logs
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
MODE="bootstrap"
RUNS=3
KEEP_LOGS="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h)
      usage
      ;;
    --keep-logs)
      KEEP_LOGS="true"
      shift
      ;;
    bootstrap|full-bootstrap)
      MODE="$1"
      shift
      ;;
    *)
      # Try to interpret as number of runs
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        RUNS="$1"
        shift
      else
        echo "Error: unknown argument '$1'" >&2
        echo "Run '$(basename "$0") --help' for usage." >&2
        exit 1
      fi
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
# Log directory and summary file
# ---------------------------------------------------------------------------
LOG_DIR="${REPO_ROOT}/logs/benchmark"
TIMESTAMP="$(date '+%Y%m%d_%H%M%S')"
SUMMARY_FILE="${LOG_DIR}/summary_${TIMESTAMP}.json"

# ---------------------------------------------------------------------------
# Print header
# ---------------------------------------------------------------------------
echo ""
platform_summary
echo ""
echo "=== Benchmark Configuration ==="
echo "  Mode:       $MODE"
echo "  Script:     $BOOTSTRAP_SCRIPT"
echo "  Runs:       $RUNS"
echo "  Log dir:    $LOG_DIR"
echo "  Keep logs:  $KEEP_LOGS"
echo "================================"
echo ""

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

echo "Pre-flight checks passed."
echo ""

# ---------------------------------------------------------------------------
# Clean previous logs unless --keep-logs
# ---------------------------------------------------------------------------
mkdir -p "$LOG_DIR"

if [[ "$KEEP_LOGS" != "true" ]]; then
  echo "Cleaning previous benchmark logs..."
  rm -f "${LOG_DIR}"/run_*.json
  rm -f "${LOG_DIR}"/.monitor_*
  echo ""
fi

# ---------------------------------------------------------------------------
# Run benchmark loop
# ---------------------------------------------------------------------------
for run in $(seq 1 "$RUNS"); do
  echo "============================================================"
  echo "  Benchmark Run ${run} / ${RUNS}"
  echo "============================================================"
  echo ""

  # Tear down any existing cluster (allow failure)
  echo ">>> Tearing down existing cluster..."
  bash "${SCRIPT_DIR}/cluster-down.sh" || true
  sleep 2

  # Export benchmark environment variables
  export BENCHMARK_MODE=1
  export BENCHMARK_RUN_NUMBER="$run"

  # Run the bootstrap script
  echo ">>> Starting ${MODE} (run ${run})..."
  bash "$BOOTSTRAP_SCRIPT"

  # Unset benchmark environment variables
  unset BENCHMARK_MODE
  unset BENCHMARK_RUN_NUMBER

  echo ""
  echo ">>> Run ${run} complete."
  echo ""
done

# ---------------------------------------------------------------------------
# Aggregate results
# ---------------------------------------------------------------------------
echo "============================================================"
echo "  Aggregating benchmark results..."
echo "============================================================"
echo ""

python3 "${SCRIPT_DIR}/lib/aggregate-stats.py" "$LOG_DIR" "$RUNS" "$MODE" "$SUMMARY_FILE"

echo ""
echo "Summary written to: ${SUMMARY_FILE}"
echo ""
