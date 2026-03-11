#!/usr/bin/env bash
# scripts/lib/monitor.sh — Resource monitor for bootstrap steps
# Samples CPU/memory/swap/disk/Docker stats in the background during step execution.
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
_MONITOR_DOCKER_INTERVAL=10

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
# _monitor_mem_all — Get memory usage in MB and percentage
# Returns: "used_mb mem_percent"
# ---------------------------------------------------------------------------
_monitor_mem_all() {
  local total_mb used_mb pct
  total_mb="$(platform_memory_mb)"
  total_mb="${total_mb:-1}"
  used_mb="$(_monitor_mem_mb)"
  used_mb="${used_mb:-0}"
  pct="$(awk -v used="$used_mb" -v total="$total_mb" 'BEGIN { printf "%.1f", used * 100.0 / total }')"
  echo "${used_mb} ${pct}"
}

# ---------------------------------------------------------------------------
# _monitor_swap_mb — Get current swap usage in MB
# ---------------------------------------------------------------------------
_monitor_swap_mb() {
  case "$PLATFORM_OS" in
    darwin)
      sysctl vm.swapusage 2>/dev/null | awk '{
        for (i = 1; i <= NF; i++)
          if ($i == "used") {
            val = $(i + 2)
            gsub(/[^0-9.]/, "", val)
            printf "%d", val
            exit
          }
      }' || echo "0"
      ;;
    linux)
      awk '/^SwapTotal:/{t=$2} /^SwapFree:/{f=$2} END{print int((t - f) / 1024)}' \
        /proc/meminfo 2>/dev/null || echo "0"
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
# _monitor_sampler <tmp_dir> — Background sampler loop
# Samples system metrics every _MONITOR_INTERVAL seconds
# CSV columns: timestamp,cpu_percent,mem_mb,mem_percent,swap_mb,
#              disk_read_kbps,disk_write_kbps,docker_containers
# ---------------------------------------------------------------------------
_monitor_sampler() {
  local tmp_dir="$1"
  local csv_file="${tmp_dir}/samples.csv"

  echo "timestamp,cpu_percent,mem_mb,mem_percent,swap_mb,disk_read_kbps,disk_write_kbps,docker_containers" \
    > "$csv_file"

  # Variables for the sampling loop
  local prev_disk_read=0 prev_disk_write=0 prev_disk_ts=0
  local ts cpu mem_all mem_mb mem_pct swap docker_count
  local disk_r_kbps disk_w_kbps
  local iostat_mbps disk_raw cur_read cur_write elapsed

  while true; do
    disk_r_kbps=0
    disk_w_kbps=0
    ts="$(date +%s)"
    cpu="$(_monitor_cpu_percent)"

    # Memory (MB + %)
    mem_all="$(_monitor_mem_all)"
    mem_mb="$(echo "$mem_all" | awk '{print $1}')"
    mem_pct="$(echo "$mem_all" | awk '{print $2}')"

    # Swap
    swap="$(_monitor_swap_mb)"

    # Disk I/O
    case "$PLATFORM_OS" in
      darwin)
        # macOS: iostat gives combined instant throughput (MB/s)
        iostat_mbps="$(iostat -d -c 1 2>/dev/null \
          | awk 'NR==3 {t=0; for(i=3;i<=NF;i+=3) t+=$i; print t+0}')" || iostat_mbps="0"
        iostat_mbps="${iostat_mbps:-0}"
        disk_r_kbps="$(awk -v mbps="$iostat_mbps" 'BEGIN {printf "%d", mbps * 1024}')"
        disk_w_kbps=0
        ;;
      linux)
        # Linux: compute delta from cumulative /proc/diskstats
        disk_raw="$(awk \
          '$3 ~ /^(sd[a-z]|vd[a-z]|nvme[0-9]+n[0-9]+)$/ {rs += $6; ws += $10} END {printf "%d %d", rs * 512, ws * 512}' \
          /proc/diskstats 2>/dev/null)" || disk_raw="0 0"
        cur_read="$(echo "$disk_raw" | awk '{print $1}')"
        cur_write="$(echo "$disk_raw" | awk '{print $2}')"
        if [[ "$prev_disk_ts" -gt 0 ]]; then
          elapsed=$(( ts - prev_disk_ts ))
          if [[ "$elapsed" -gt 0 ]]; then
            disk_r_kbps=$(( (cur_read - prev_disk_read) / 1024 / elapsed ))
            disk_w_kbps=$(( (cur_write - prev_disk_write) / 1024 / elapsed ))
          fi
        fi
        prev_disk_read="$cur_read"
        prev_disk_write="$cur_write"
        prev_disk_ts="$ts"
        ;;
    esac

    docker_count="$(_monitor_docker_containers)"
    echo "${ts},${cpu},${mem_mb},${mem_pct},${swap},${disk_r_kbps},${disk_w_kbps},${docker_count}" \
      >> "$csv_file"
    sleep "$_MONITOR_INTERVAL"
  done
}

# ---------------------------------------------------------------------------
# _monitor_docker_sampler <tmp_dir> — Background Docker container stats sampler
# Samples per-container CPU/memory every _MONITOR_DOCKER_INTERVAL seconds
# Output: docker_stats.jsonl (one JSON object per line)
# ---------------------------------------------------------------------------
_monitor_docker_sampler() {
  local tmp_dir="$1"
  local jsonl_file="${tmp_dir}/docker_stats.jsonl"
  : > "$jsonl_file"

  local ts stats_output json_line first
  local name cpu_pct mem_usage mem_mb

  while true; do
    ts="$(date +%s)"
    stats_output="$(docker stats --no-stream \
      --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' 2>/dev/null)" || {
      sleep "$_MONITOR_DOCKER_INTERVAL"
      continue
    }

    json_line="{\"ts\":${ts},\"containers\":["
    first=true
    while IFS=$'\t' read -r name cpu_pct mem_usage; do
      [[ -z "$name" ]] && continue
      cpu_pct="${cpu_pct//%/}"
      mem_mb="$(echo "$mem_usage" | awk '{
        val = $1 + 0
        unit = $1
        gsub(/[0-9.]/, "", unit)
        if (unit == "GiB" || unit == "GB") val = val * 1024
        else if (unit == "KiB" || unit == "KB") val = val / 1024
        printf "%d", val
      }')"
      if [[ "$first" == "true" ]]; then
        first=false
      else
        json_line+=","
      fi
      json_line+="{\"name\":\"${name}\",\"cpu_percent\":${cpu_pct:-0},\"mem_mb\":${mem_mb:-0}}"
    done <<< "$stats_output"
    json_line+="]}"

    echo "$json_line" >> "$jsonl_file"
    sleep "$_MONITOR_DOCKER_INTERVAL"
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

  # Launch system metrics sampler
  _monitor_sampler "$tmp_dir" &
  local sampler_pid=$!
  echo "$sampler_pid" > "${tmp_dir}/pid"
  disown "$sampler_pid" 2>/dev/null || true

  # Launch Docker container-level stats sampler (10s cadence)
  _monitor_docker_sampler "$tmp_dir" &
  local docker_pid=$!
  echo "$docker_pid" > "${tmp_dir}/docker_pid"
  disown "$docker_pid" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# stop_monitor <step_name>
# Kills samplers, computes summary, outputs JSON to stdout, cleans up
# ---------------------------------------------------------------------------
stop_monitor() {
  local step_name="${1:?Usage: stop_monitor <step_name>}"
  local tmp_dir="${REPO_ROOT}/logs/benchmark/.monitor_${step_name}"
  local csv_file="${tmp_dir}/samples.csv"
  local pid_file="${tmp_dir}/pid"
  local docker_pid_file="${tmp_dir}/docker_pid"
  local docker_jsonl="${tmp_dir}/docker_stats.jsonl"
  local summary_file="${REPO_ROOT}/logs/benchmark/.monitor_${step_name}_summary.json"

  # Kill the background samplers and wait for them to die
  local p pf tries
  for pf in "$pid_file" "$docker_pid_file"; do
    if [[ -f "$pf" ]]; then
      p="$(cat "$pf")"
      kill "$p" 2>/dev/null || true
      tries=0
      while kill -0 "$p" 2>/dev/null && [[ $tries -lt 20 ]]; do
        sleep 0.1
        tries=$((tries + 1))
      done
    fi
  done

  # Read initial memory
  local mem_start=0
  if [[ -f "${tmp_dir}/mem_start" ]]; then
    mem_start="$(cat "${tmp_dir}/mem_start")"
    mem_start="${mem_start:-0}"
  fi

  # Calculate summary from extended CSV (8 columns)
  local csv_summary
  if [[ -f "$csv_file" ]] && [[ "$(wc -l < "$csv_file" | tr -d ' ')" -gt 1 ]]; then
    csv_summary="$(awk -F',' '
      NR == 1 { next }
      {
        cpu = $2 + 0; mem = $3 + 0; mem_pct = $4 + 0; swap = $5 + 0
        disk_r = $6 + 0; disk_w = $7 + 0; docker = $8 + 0
        cpu_sum += cpu; mem_pct_sum += mem_pct
        disk_r_sum += disk_r; disk_w_sum += disk_w
        count++
        if (cpu > cpu_peak) cpu_peak = cpu
        if (mem > mem_peak) mem_peak = mem
        if (mem_pct > mem_pct_peak) mem_pct_peak = mem_pct
        if (swap > swap_peak) swap_peak = swap
        if (disk_r > disk_r_peak) disk_r_peak = disk_r
        if (disk_w > disk_w_peak) disk_w_peak = disk_w
        if (docker > docker_max) docker_max = docker
      }
      END {
        if (count > 0) {
          cpu_avg = cpu_sum / count
          mem_pct_avg = mem_pct_sum / count
          disk_r_avg = disk_r_sum / count
          disk_w_avg = disk_w_sum / count
        } else {
          cpu_avg = 0; mem_pct_avg = 0; disk_r_avg = 0; disk_w_avg = 0
        }
        printf "%.1f %.1f %d %.1f %.1f %d %.1f %.1f %.1f %.1f %d",
          cpu_avg, cpu_peak, mem_peak, mem_pct_avg, mem_pct_peak,
          swap_peak, disk_r_avg, disk_w_avg, disk_r_peak, disk_w_peak, docker_max
      }
    ' "$csv_file")"
  else
    csv_summary="0.0 0.0 0 0.0 0.0 0 0.0 0.0 0.0 0.0 0"
  fi

  # Parse CSV summary fields
  local cpu_avg cpu_peak mem_peak mem_pct_avg mem_pct_peak swap_peak
  local disk_r_avg disk_w_avg disk_r_peak disk_w_peak docker_max
  read -r cpu_avg cpu_peak mem_peak mem_pct_avg mem_pct_peak \
    swap_peak disk_r_avg disk_w_avg disk_r_peak disk_w_peak docker_max \
    <<< "$csv_summary"

  # Process Docker container-level stats from JSONL
  local docker_container_stats="[]"
  if [[ -f "$docker_jsonl" ]] && [[ -s "$docker_jsonl" ]]; then
    docker_container_stats="$(python3 -c "
import json, sys
from collections import defaultdict
containers = defaultdict(lambda: {'cpu': [], 'mem': []})
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
    except (json.JSONDecodeError, ValueError):
        continue
    for c in data.get('containers', []):
        name = c['name']
        containers[name]['cpu'].append(float(c.get('cpu_percent', 0)))
        containers[name]['mem'].append(int(c.get('mem_mb', 0)))
result = []
for name, stats in sorted(containers.items()):
    cpus = stats['cpu']
    mems = stats['mem']
    result.append({
        'name': name,
        'cpu_avg_percent': round(sum(cpus) / len(cpus), 1) if cpus else 0,
        'cpu_peak_percent': round(max(cpus), 1) if cpus else 0,
        'mem_peak_mb': max(mems) if mems else 0
    })
print(json.dumps(result))
" < "$docker_jsonl" 2>/dev/null)" || docker_container_stats="[]"
  fi

  # Build summary JSON
  local summary
  summary="{\"cpu_avg_percent\": ${cpu_avg}, \"cpu_peak_percent\": ${cpu_peak}, \"mem_start_mb\": ${mem_start}, \"mem_peak_mb\": ${mem_peak}, \"mem_avg_percent\": ${mem_pct_avg}, \"mem_peak_percent\": ${mem_pct_peak}, \"swap_peak_mb\": ${swap_peak}, \"disk_read_avg_kbps\": ${disk_r_avg}, \"disk_write_avg_kbps\": ${disk_w_avg}, \"disk_read_peak_kbps\": ${disk_r_peak}, \"disk_write_peak_kbps\": ${disk_w_peak}, \"docker_containers\": ${docker_max}, \"docker_container_stats\": ${docker_container_stats}}"

  # Write summary JSON
  echo "$summary" > "$summary_file"

  # Output the summary JSON to stdout (consumed by timing.sh)
  echo "$summary"

  # Clean up temp dir
  rm -rf "$tmp_dir"
}

# Mark as loaded
_MONITOR_LOADED="true"
