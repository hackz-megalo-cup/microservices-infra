#!/usr/bin/env bash
# scripts/lib/monitor.sh — Resource monitor for bootstrap steps
# Samples CPU/memory/Docker stats in the background during step execution.
# Safe to source multiple times (idempotent via guard variable).

# Idempotency guard
if [[ "${_MONITOR_LOADED:-}" == "true" ]]; then
  return 0
fi

# ---------------------------------------------------------------------------
# Derive REPO_ROOT if not already set
# ---------------------------------------------------------------------------
if [[ -z "${REPO_ROOT:-}" ]]; then
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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
# Configuration
# ---------------------------------------------------------------------------
_MONITOR_INTERVAL=2

# ---------------------------------------------------------------------------
# _monitor_mem_mb — Get current memory usage in MB
# ---------------------------------------------------------------------------
_monitor_mem_mb() {
  case "$PLATFORM_OS" in
    darwin)
      local page_size
      page_size="$(sysctl -n hw.pagesize 2>/dev/null)" || { echo "0"; return; }
      local vm_output
      vm_output="$(vm_stat 2>/dev/null)" || { echo "0"; return; }
      local pages_active pages_wired
      pages_active="$(echo "$vm_output" | awk '/Pages active:/ {gsub(/\./,"",$3); print $3}')"
      pages_wired="$(echo "$vm_output" | awk '/Pages wired down:/ {gsub(/\./,"",$4); print $4}')"
      pages_active="${pages_active:-0}"
      pages_wired="${pages_wired:-0}"
      echo $(( (pages_active + pages_wired) * page_size / 1048576 ))
      ;;
    linux)
      local mem_total mem_available
      mem_total="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null)" || { echo "0"; return; }
      mem_available="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null)" || { echo "0"; return; }
      mem_total="${mem_total:-0}"
      mem_available="${mem_available:-0}"
      echo $(( (mem_total - mem_available) / 1024 ))
      ;;
  esac
}

# ---------------------------------------------------------------------------
# _monitor_cpu_percent — Get current CPU usage percentage
# ---------------------------------------------------------------------------
_monitor_cpu_percent() {
  case "$PLATFORM_OS" in
    darwin)
      local top_output
      top_output="$(top -l 1 -s 0 2>/dev/null)" || { echo "0.0"; return; }
      local cpu_usage
      cpu_usage="$(echo "$top_output" | awk '/^CPU usage:/ {
        user = $3; sys = $5;
        gsub(/%/, "", user); gsub(/%/, "", sys);
        printf "%.1f", user + sys
      }')"
      echo "${cpu_usage:-0.0}"
      ;;
    linux)
      # Read /proc/stat twice with 1 second interval
      local line1 line2
      line1="$(head -1 /proc/stat 2>/dev/null)" || { echo "0.0"; return; }
      sleep 1
      line2="$(head -1 /proc/stat 2>/dev/null)" || { echo "0.0"; return; }

      echo "$line1
$line2" | awk '
        NR==1 {
          total1 = 0
          for (i=2; i<=NF; i++) total1 += $i
          idle1 = $5
        }
        NR==2 {
          total2 = 0
          for (i=2; i<=NF; i++) total2 += $i
          idle2 = $5
          diff_total = total2 - total1
          diff_idle = idle2 - idle1
          if (diff_total > 0)
            printf "%.1f", (diff_total - diff_idle) * 100.0 / diff_total
          else
            printf "0.0"
        }'
      ;;
  esac
}

# ---------------------------------------------------------------------------
# _monitor_docker_containers — Count running Docker containers
# ---------------------------------------------------------------------------
_monitor_docker_containers() {
  local count
  count="$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
  echo "${count:-0}"
}

# ---------------------------------------------------------------------------
# _monitor_sampler <step_name> <tmp_dir> — Background sampler loop
# ---------------------------------------------------------------------------
_monitor_sampler() {
  local step_name="$1"
  local tmp_dir="$2"
  local csv_file="${tmp_dir}/samples.csv"

  # Write CSV header
  echo "timestamp,cpu_percent,mem_mb,docker_containers" > "$csv_file"

  # Sampling loop
  while true; do
    local ts cpu mem docker_count
    ts="$(date +%s)"
    cpu="$(_monitor_cpu_percent)"
    mem="$(_monitor_mem_mb)"
    docker_count="$(_monitor_docker_containers)"
    echo "${ts},${cpu},${mem},${docker_count}" >> "$csv_file"
    sleep "$_MONITOR_INTERVAL"
  done
}

# ---------------------------------------------------------------------------
# start_monitor <step_name>
# ---------------------------------------------------------------------------
start_monitor() {
  local step_name="${1:?Usage: start_monitor <step_name>}"
  local tmp_dir="${REPO_ROOT}/logs/benchmark/.monitor_${step_name}"

  mkdir -p "$tmp_dir"

  # Record initial memory
  _monitor_mem_mb > "${tmp_dir}/mem_start"

  # Launch sampler in background
  _monitor_sampler "$step_name" "$tmp_dir" &
  local sampler_pid=$!
  echo "$sampler_pid" > "${tmp_dir}/pid"
  disown "$sampler_pid" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# stop_monitor <step_name>
# Kills sampler, computes summary, outputs JSON to stdout, cleans up
# ---------------------------------------------------------------------------
stop_monitor() {
  local step_name="${1:?Usage: stop_monitor <step_name>}"
  local tmp_dir="${REPO_ROOT}/logs/benchmark/.monitor_${step_name}"
  local csv_file="${tmp_dir}/samples.csv"
  local pid_file="${tmp_dir}/pid"
  local summary_file="${REPO_ROOT}/logs/benchmark/.monitor_${step_name}_summary.json"

  # Kill the background sampler
  if [[ -f "$pid_file" ]]; then
    local sampler_pid
    sampler_pid="$(cat "$pid_file")"
    kill "$sampler_pid" 2>/dev/null || true
    wait "$sampler_pid" 2>/dev/null || true
  fi

  # Read initial memory
  local mem_start=0
  if [[ -f "${tmp_dir}/mem_start" ]]; then
    mem_start="$(cat "${tmp_dir}/mem_start")"
    mem_start="${mem_start:-0}"
  fi

  # Calculate summary from CSV using awk
  local summary
  if [[ -f "$csv_file" ]] && [[ "$(wc -l < "$csv_file" | tr -d ' ')" -gt 1 ]]; then
    summary="$(awk -F',' '
      NR == 1 { next }  # skip header
      {
        cpu = $2 + 0
        mem = $3 + 0
        docker = $4 + 0
        cpu_sum += cpu
        count++
        if (cpu > cpu_peak) cpu_peak = cpu
        if (mem > mem_peak) mem_peak = mem
        if (docker > docker_max) docker_max = docker
      }
      END {
        if (count > 0)
          cpu_avg = cpu_sum / count
        else
          cpu_avg = 0
        printf "{\"cpu_avg_percent\": %.1f, \"cpu_peak_percent\": %.1f, \"mem_start_mb\": %d, \"mem_peak_mb\": %d, \"docker_containers\": %d}",
          cpu_avg, cpu_peak, '"$mem_start"', mem_peak, docker_max
      }
    ' "$csv_file")"
  else
    # No samples collected — produce zeroed summary
    summary="{\"cpu_avg_percent\": 0.0, \"cpu_peak_percent\": 0.0, \"mem_start_mb\": ${mem_start}, \"mem_peak_mb\": 0, \"docker_containers\": 0}"
  fi

  # Write summary JSON
  echo "$summary" > "$summary_file"

  # Output the summary JSON to stdout (consumed by timing.sh)
  echo "$summary"

  # Clean up temp dir
  rm -rf "$tmp_dir"
}

# Mark as loaded
_MONITOR_LOADED="true"
