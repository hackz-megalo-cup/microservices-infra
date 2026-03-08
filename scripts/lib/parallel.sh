#!/usr/bin/env bash
# scripts/lib/parallel.sh — Parallel execution helper for bootstrap scripts
# Runs multiple steps concurrently with log isolation and error handling.
# Safe to source multiple times (idempotent via guard variable).

# Idempotency guard
if [[ "${_PARALLEL_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || exit 0
fi

# ---------------------------------------------------------------------------
# Derive REPO_ROOT if not already set
# ---------------------------------------------------------------------------
if [[ -z "${REPO_ROOT:-}" ]]; then
  # Support both bash and zsh
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  elif [[ -n "${(%):-%x}" ]]; then
    REPO_ROOT="$(cd "$(dirname "${(%):-%x}")/../.." && pwd)"
  else
    REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  fi
  export REPO_ROOT
fi

# ---------------------------------------------------------------------------
# Temp directory for log files, with cleanup trap
# ---------------------------------------------------------------------------
_PARALLEL_TMPDIR=""

_parallel_cleanup() {
  if [[ -n "$_PARALLEL_TMPDIR" ]] && [[ -d "$_PARALLEL_TMPDIR" ]]; then
    rm -rf "$_PARALLEL_TMPDIR"
  fi
}
trap _parallel_cleanup EXIT

_parallel_ensure_tmpdir() {
  if [[ -z "$_PARALLEL_TMPDIR" ]] || [[ ! -d "$_PARALLEL_TMPDIR" ]]; then
    _PARALLEL_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/parallel_run.XXXXXX")"
  fi
}

# ---------------------------------------------------------------------------
# parallel_run "step_name:command args..." ["step_name2:command2 args..."] ...
#
# Runs each command in a background subshell with isolated log output.
# After all complete, prints each step's output and returns 1 if any failed.
# Uses eval so that shell functions (e.g. _step_*) work inside subshells.
# ---------------------------------------------------------------------------
parallel_run() {
  _parallel_ensure_tmpdir

  local -a pids=()
  local -a names=()
  local -a logfiles=()
  local i=0

  for arg in "$@"; do
    # Split on first ':' to get name and command
    local name="${arg%%:*}"
    local cmd="${arg#*:}"

    names+=("$name")
    local logfile="${_PARALLEL_TMPDIR}/${name}.log"
    logfiles+=("$logfile")

    echo "  [parallel] starting: ${name}"

    # Run in background subshell with output redirected to logfile
    (
      eval "$cmd"
    ) > "$logfile" 2>&1 &
    pids+=($!)

    i=$(( i + 1 ))
  done

  # Wait for all PIDs and track exit codes
  local -a exit_codes=()
  local any_failed=0
  for j in "${!pids[@]}"; do
    local ec=0
    wait "${pids[$j]}" || ec=$?
    exit_codes+=("$ec")
    if [[ "$ec" -ne 0 ]]; then
      any_failed=1
    fi
  done

  # Print each step's log output with headers
  for j in "${!names[@]}"; do
    echo "  --- [${names[$j]}] output ---"
    if [[ -f "${logfiles[$j]}" ]]; then
      cat "${logfiles[$j]}"
    fi
    echo "  --- [${names[$j]}] end ---"
  done

  # Report failures
  if [[ "$any_failed" -ne 0 ]]; then
    echo ""
    echo "  [parallel] ERROR: the following steps failed:" >&2
    for j in "${!names[@]}"; do
      if [[ "${exit_codes[$j]}" -ne 0 ]]; then
        echo "    - ${names[$j]} (exit code ${exit_codes[$j]})" >&2
      fi
    done
    return 1
  fi

  return 0
}

# ---------------------------------------------------------------------------
# preload_images <cluster_name> <image1> [image2 ...]
#
# Pulls all images in parallel, then loads them into the kind cluster.
# ---------------------------------------------------------------------------
preload_images() {
  local cluster_name="${1:?Usage: preload_images <cluster_name> <image1> [image2 ...]}"
  shift

  if [[ $# -eq 0 ]]; then
    echo "preload_images: no images specified" >&2
    return 1
  fi

  local -a images=("$@")
  local -a pull_pids=()

  echo "  [preload] Pulling ${#images[@]} images in parallel..."

  # Pull all images in parallel
  for img in "${images[@]}"; do
    docker pull "$img" &>/dev/null &
    pull_pids+=($!)
  done

  # Wait for all pulls to complete
  local pull_failed=0
  for j in "${!pull_pids[@]}"; do
    if ! wait "${pull_pids[$j]}"; then
      echo "  [preload] WARNING: failed to pull ${images[$j]}" >&2
      pull_failed=1
    fi
  done

  if [[ "$pull_failed" -ne 0 ]]; then
    echo "  [preload] Some pulls failed, continuing with available images..."
  fi

  # Load all images into kind cluster
  echo "  [preload] Loading images into kind cluster '${cluster_name}'..."
  kind load docker-image "${images[@]}" --name "$cluster_name" 2>/dev/null || {
    echo "  [preload] WARNING: kind load failed, trying images one by one..." >&2
    for img in "${images[@]}"; do
      kind load docker-image "$img" --name "$cluster_name" 2>/dev/null || \
        echo "  [preload] WARNING: failed to load ${img}" >&2
    done
  }

  echo "  [preload] Done loading images."
}

# Mark as loaded
_PARALLEL_LOADED="true"
