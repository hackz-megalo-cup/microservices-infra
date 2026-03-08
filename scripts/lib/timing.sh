#!/usr/bin/env bash
# scripts/lib/timing.sh — Timing framework for bootstrap scripts
# Tracks per-step durations and outputs summary reports.
# Safe to source multiple times (idempotent via guard variable).

# Idempotency guard
if [[ "${_TIMING_LOADED:-}" == "true" ]]; then
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
# Auto-source platform.sh if not already loaded
# ---------------------------------------------------------------------------
if [[ "${_PLATFORM_LOADED:-}" != "true" ]]; then
  # shellcheck source=platform.sh
  source "${REPO_ROOT}/scripts/lib/platform.sh"
fi

# ---------------------------------------------------------------------------
# High-resolution timestamp (seconds with millisecond precision)
# ---------------------------------------------------------------------------
_timing_now() {
  case "$PLATFORM_OS" in
    darwin)
      python3 -c 'import time; print(f"{time.time():.3f}")'
      ;;
    linux)
      date +%s.%N
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Session state arrays
# ---------------------------------------------------------------------------
_TIMING_SESSION_NAME=""
_TIMING_SESSION_START=""
_TIMING_STEP_NAMES=()
_TIMING_STEP_DURATIONS=()
_TIMING_STEP_EXIT_CODES=()
_TIMING_STEP_RESOURCES=()
_TIMING_STEP_COUNT=0

# ---------------------------------------------------------------------------
# timing_init <session_name>
# Sets up session state, creates log directory, prints header
# ---------------------------------------------------------------------------
timing_init() {
  local session_name="${1:?Usage: timing_init <session_name>}"

  _TIMING_SESSION_NAME="$session_name"
  _TIMING_SESSION_START="$(_timing_now)"
  _TIMING_STEP_NAMES=()
  _TIMING_STEP_DURATIONS=()
  _TIMING_STEP_EXIT_CODES=()
  _TIMING_STEP_RESOURCES=()
  _TIMING_STEP_COUNT=0

  # Ensure benchmark log directory exists
  mkdir -p "${REPO_ROOT}/logs/benchmark"

  # Print header
  echo "============================================================"
  echo "  Session:   ${_TIMING_SESSION_NAME}"
  echo "  Date:      $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "  Platform:  ${PLATFORM_OS} / ${PLATFORM_ARCH} (${PLATFORM_NIX_SYSTEM})"
  echo "  CPU:       $(platform_cpu_model)"
  echo "  Cores:     $(platform_cpu_cores)"
  echo "  Memory:    $(platform_memory_gb) GB"
  echo "============================================================"
  echo ""
}

# ---------------------------------------------------------------------------
# timed_step <step_name> <command...>
# Runs a command, records timing and exit code, prints status
# ---------------------------------------------------------------------------
timed_step() {
  local step_name="${1:?Usage: timed_step <step_name> <command...>}"
  shift

  echo ">>> [${step_name}] starting..."

  # Record start time
  local step_start
  step_start="$(_timing_now)"

  # Start resource monitor if available
  local monitor_available="false"
  if type start_monitor &>/dev/null; then
    monitor_available="true"
    start_monitor "$step_name"
  fi

  # Run the command, capture exit code
  local exit_code=0
  "$@" || exit_code=$?

  # Stop resource monitor if available
  local resource_data=""
  if [[ "$monitor_available" == "true" ]] && type stop_monitor &>/dev/null; then
    resource_data="$(stop_monitor "$step_name" 2>/dev/null)" || true
  fi

  # Record end time and calculate duration
  local step_end
  step_end="$(_timing_now)"
  local duration
  duration="$(python3 -c "print(f'{${step_end} - ${step_start}:.3f}')")"

  # Store step data (use 1-based index for bash/zsh compatibility)
  _TIMING_STEP_COUNT=$(( _TIMING_STEP_COUNT + 1 ))
  _TIMING_STEP_NAMES[${_TIMING_STEP_COUNT}]="$step_name"
  _TIMING_STEP_DURATIONS[${_TIMING_STEP_COUNT}]="$duration"
  _TIMING_STEP_EXIT_CODES[${_TIMING_STEP_COUNT}]="$exit_code"
  _TIMING_STEP_RESOURCES[${_TIMING_STEP_COUNT}]="${resource_data:-}"

  if [[ "$exit_code" -eq 0 ]]; then
    echo "<<< [${step_name}] OK — ${duration}s"
  else
    echo "<<< [${step_name}] FAIL (exit code ${exit_code}) — ${duration}s" >&2
    timing_report
    exit "$exit_code"
  fi
}

# ---------------------------------------------------------------------------
# timing_report
# Prints formatted table and writes JSON benchmark file
# ---------------------------------------------------------------------------
timing_report() {
  local session_end
  session_end="$(_timing_now)"
  local total_duration
  total_duration="$(python3 -c "print(f'{${session_end} - ${_TIMING_SESSION_START}:.3f}')")"

  echo ""
  echo "============================================================"
  echo "  Timing Report: ${_TIMING_SESSION_NAME}"
  echo "============================================================"
  printf "  %-30s %10s   %s\n" "Step" "Duration" "Status"
  printf "  %-30s %10s   %s\n" "------------------------------" "----------" "------"

  local i=1
  while [[ "$i" -le "$_TIMING_STEP_COUNT" ]]; do
    local name="${_TIMING_STEP_NAMES[$i]}"
    local dur="${_TIMING_STEP_DURATIONS[$i]}"
    local code="${_TIMING_STEP_EXIT_CODES[$i]}"
    local step_status="OK"
    if [[ "$code" -ne 0 ]]; then
      step_status="FAIL"
    fi
    printf "  %-30s %9ss   %s\n" "$name" "$dur" "$step_status"
    i=$(( i + 1 ))
  done

  printf "  %-30s %10s   %s\n" "------------------------------" "----------" "------"
  printf "  %-30s %9ss\n" "TOTAL" "$total_duration"
  echo "============================================================"
  echo ""

  # ---------------------------------------------------------------------------
  # Write JSON benchmark file
  # ---------------------------------------------------------------------------
  local run_number="${BENCHMARK_RUN_NUMBER:-1}"
  local json_file="${REPO_ROOT}/logs/benchmark/run_${run_number}.json"
  local timestamp
  timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  # Build steps JSON array
  local steps_json="["
  i=1
  while [[ "$i" -le "$_TIMING_STEP_COUNT" ]]; do
    local name="${_TIMING_STEP_NAMES[$i]}"
    local dur="${_TIMING_STEP_DURATIONS[$i]}"
    local code="${_TIMING_STEP_EXIT_CODES[$i]}"
    local res="${_TIMING_STEP_RESOURCES[$i]}"

    if [[ "$i" -gt 1 ]]; then
      steps_json+=","
    fi

    if [[ -n "$res" ]]; then
      steps_json+="{
      \"name\": \"${name}\",
      \"duration_sec\": ${dur},
      \"exit_code\": ${code},
      \"resources\": ${res}
    }"
    else
      steps_json+="{
      \"name\": \"${name}\",
      \"duration_sec\": ${dur},
      \"exit_code\": ${code}
    }"
    fi
    i=$(( i + 1 ))
  done
  steps_json+="]"

  # Build full JSON document
  local docker_ver
  docker_ver="$(platform_docker_version)"
  local cpu_model
  cpu_model="$(platform_cpu_model)"
  local cpu_cores
  cpu_cores="$(platform_cpu_cores)"
  local memory_gb
  memory_gb="$(platform_memory_gb)"

  cat > "$json_file" <<JSON_EOF
{
  "session": {
    "timestamp": "${timestamp}",
    "mode": "${_TIMING_SESSION_NAME}",
    "run_number": ${run_number},
    "host": {
      "os": "${PLATFORM_OS}",
      "arch": "${PLATFORM_ARCH}",
      "nix_system": "${PLATFORM_NIX_SYSTEM}",
      "cpu_model": "${cpu_model}",
      "cpu_cores": ${cpu_cores},
      "memory_gb": ${memory_gb},
      "docker_version": "${docker_ver}",
      "is_wsl": ${PLATFORM_IS_WSL}
    }
  },
  "steps": ${steps_json},
  "total_duration_sec": ${total_duration}
}
JSON_EOF

  echo "Benchmark saved to: ${json_file}"
}

# Mark as loaded
_TIMING_LOADED="true"
