#!/usr/bin/env bash
# scripts/lib/platform.sh — Unified platform detection library
# Source this file to set PLATFORM_* variables and helper functions.
# Safe to source multiple times (idempotent via guard variable).

# Idempotency guard
if [[ "${_PLATFORM_LOADED:-}" == "true" ]]; then
  return 0
fi

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
PLATFORM_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$PLATFORM_OS" in
  darwin|linux) ;;
  *)
    echo "platform.sh: unsupported OS: $PLATFORM_OS" >&2
    return 1
    ;;
esac

# ---------------------------------------------------------------------------
# Architecture detection — normalize to Nix naming
# ---------------------------------------------------------------------------
_RAW_ARCH="$(uname -m)"
case "$_RAW_ARCH" in
  arm64)   PLATFORM_ARCH="aarch64" ;;
  aarch64) PLATFORM_ARCH="aarch64" ;;
  x86_64)  PLATFORM_ARCH="x86_64"  ;;
  amd64)   PLATFORM_ARCH="x86_64"  ;;
  *)
    echo "platform.sh: unsupported architecture: $_RAW_ARCH" >&2
    return 1
    ;;
esac
unset _RAW_ARCH

# ---------------------------------------------------------------------------
# Derived system strings
# ---------------------------------------------------------------------------
PLATFORM_NIX_SYSTEM="${PLATFORM_ARCH}-${PLATFORM_OS}"
PLATFORM_LINUX_SYSTEM="${PLATFORM_ARCH}-linux"

# ---------------------------------------------------------------------------
# WSL2 detection
# ---------------------------------------------------------------------------
if [[ "$PLATFORM_OS" == "linux" ]] && [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version 2>/dev/null; then
  PLATFORM_IS_WSL="true"
else
  PLATFORM_IS_WSL="false"
fi

# ---------------------------------------------------------------------------
# Docker architecture string
# ---------------------------------------------------------------------------
case "$PLATFORM_ARCH" in
  aarch64) PLATFORM_DOCKER_ARCH="linux/arm64" ;;
  x86_64)  PLATFORM_DOCKER_ARCH="linux/amd64" ;;
esac

# ---------------------------------------------------------------------------
# Docker runtime detection (OrbStack / Docker Desktop / other)
# ---------------------------------------------------------------------------
_detect_docker_runtime() {
  if ! command -v docker &>/dev/null; then
    echo "none"
    return
  fi
  local server_os
  server_os="$(docker info --format '{{.OperatingSystem}}' 2>/dev/null)" || { echo "unknown"; return; }
  case "$server_os" in
    *OrbStack*)       echo "orbstack" ;;
    *Docker\ Desktop*) echo "docker-desktop" ;;
    *)                 echo "other" ;;
  esac
}
PLATFORM_DOCKER_RUNTIME="$(_detect_docker_runtime)"

# ---------------------------------------------------------------------------
# Export all variables
# ---------------------------------------------------------------------------
export PLATFORM_OS
export PLATFORM_ARCH
export PLATFORM_NIX_SYSTEM
export PLATFORM_LINUX_SYSTEM
export PLATFORM_IS_WSL
export PLATFORM_DOCKER_ARCH
export PLATFORM_DOCKER_RUNTIME

# ---------------------------------------------------------------------------
# Helper functions
# ---------------------------------------------------------------------------

# Returns CPU model string
platform_cpu_model() {
  case "$PLATFORM_OS" in
    darwin)
      sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "unknown"
      ;;
    linux)
      grep -m1 "^model name" /proc/cpuinfo 2>/dev/null | sed 's/^model name[[:space:]]*:[[:space:]]*//' || echo "unknown"
      ;;
  esac
}

# Returns CPU core count
platform_cpu_cores() {
  case "$PLATFORM_OS" in
    darwin)
      sysctl -n hw.ncpu 2>/dev/null || echo "0"
      ;;
    linux)
      nproc 2>/dev/null || echo "0"
      ;;
  esac
}

# Returns total memory in GB (integer)
platform_memory_gb() {
  case "$PLATFORM_OS" in
    darwin)
      local bytes
      bytes="$(sysctl -n hw.memsize 2>/dev/null)" || { echo "0"; return; }
      echo $(( bytes / 1073741824 ))
      ;;
    linux)
      local kb
      kb="$(grep -m1 "^MemTotal:" /proc/meminfo 2>/dev/null | awk '{print $2}')" || { echo "0"; return; }
      echo $(( kb / 1048576 ))
      ;;
  esac
}

# Returns total memory in MB (integer, for percentage calculations)
platform_memory_mb() {
  case "$PLATFORM_OS" in
    darwin)
      local bytes
      bytes="$(sysctl -n hw.memsize 2>/dev/null)" || { echo "0"; return; }
      echo $(( bytes / 1048576 ))
      ;;
    linux)
      local kb
      kb="$(grep -m1 "^MemTotal:" /proc/meminfo 2>/dev/null | awk '{print $2}')" || { echo "0"; return; }
      echo $(( kb / 1024 ))
      ;;
  esac
}

# Returns Docker server version
platform_docker_version() {
  docker version --format '{{.Server.Version}}' 2>/dev/null || echo "not installed"
}

# Returns Docker daemon's available memory in GB (integer)
# For Docker Desktop this reflects the VM allocation.
# For OrbStack this reflects dynamically allocated memory.
platform_docker_memory_gb() {
  local bytes
  bytes="$(docker info --format '{{.MemTotal}}' 2>/dev/null)" || { echo "0"; return; }
  echo $(( bytes / 1073741824 ))
}

# Returns Docker daemon's available CPU count
platform_docker_cpus() {
  docker info --format '{{.NCPU}}' 2>/dev/null || echo "0"
}

# Prints a summary of all detected platform info
platform_summary() {
  echo "=== Platform Summary ==="
  echo "  OS:             $PLATFORM_OS"
  echo "  Arch:           $PLATFORM_ARCH"
  echo "  Nix system:     $PLATFORM_NIX_SYSTEM"
  echo "  Linux system:   $PLATFORM_LINUX_SYSTEM"
  echo "  WSL:            $PLATFORM_IS_WSL"
  echo "  Docker arch:    $PLATFORM_DOCKER_ARCH"
  echo "  CPU model:      $(platform_cpu_model)"
  echo "  CPU cores:      $(platform_cpu_cores)"
  echo "  Memory (GB):    $(platform_memory_gb)"
  echo "  Docker runtime: $PLATFORM_DOCKER_RUNTIME"
  echo "  Docker version: $(platform_docker_version)"
  echo "========================"
}

# Prints Docker Desktop warnings for kind cluster usage
platform_docker_desktop_check() {
  if [[ "$PLATFORM_DOCKER_RUNTIME" != "docker-desktop" ]]; then
    return 0
  fi

  local docker_mem_gb docker_cpus
  docker_mem_gb="$(platform_docker_memory_gb)"
  docker_cpus="$(platform_docker_cpus)"

  echo "=========================================="
  echo "  NOTE: Docker Desktop detected"
  echo "=========================================="
  echo "  - Docker Desktop の内蔵 Kubernetes が有効だとポートが競合します"
  echo "    Settings > Kubernetes > Enable Kubernetes を OFF にしてください"
  echo "  - ポートが繋がらない場合は Docker Desktop を最新版に更新してください"

  local warnings=0
  if [[ "$docker_mem_gb" -gt 0 ]] && [[ "$docker_mem_gb" -lt 8 ]]; then
    echo ""
    echo "  WARNING: Docker Desktop のメモリが ${docker_mem_gb}GB しかありません"
    echo "    最低 8GB を推奨します（Redpanda だけで 2Gi 要求します）"
    echo "    Settings > Resources > Memory を 8GB 以上に設定してください"
    warnings=1
  fi
  if [[ "$docker_cpus" -gt 0 ]] && [[ "$docker_cpus" -lt 4 ]]; then
    echo ""
    echo "  WARNING: Docker Desktop の CPU が ${docker_cpus} コアしかありません"
    echo "    最低 4 コアを推奨します"
    echo "    Settings > Resources > CPUs を 4 以上に設定してください"
    warnings=1
  fi

  echo "=========================================="

  if [[ "$warnings" -eq 1 ]]; then
    echo ""
    echo "  リソース不足でポッドが起動しない場合があります。"
    echo "  設定変更後は Docker Desktop を再起動してください。"
    echo "  (Ctrl+C で中断、Enter で続行)"
    read -r -t 15 || true
  fi
}

# Mark as loaded
_PLATFORM_LOADED="true"
