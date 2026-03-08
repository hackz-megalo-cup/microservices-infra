#!/usr/bin/env bash
# scripts/lib/platform.sh — Unified platform detection library
# Source this file to set PLATFORM_* variables and helper functions.
# Safe to source multiple times (idempotent via guard variable).

# Idempotency guard
if [[ "${_PLATFORM_LOADED:-}" == "true" ]]; then
  return 0 2>/dev/null || exit 0
fi

# ---------------------------------------------------------------------------
# OS detection
# ---------------------------------------------------------------------------
PLATFORM_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$PLATFORM_OS" in
  darwin|linux) ;;
  *)
    echo "platform.sh: unsupported OS: $PLATFORM_OS" >&2
    return 1 2>/dev/null || exit 1
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
    return 1 2>/dev/null || exit 1
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
# Export all variables
# ---------------------------------------------------------------------------
export PLATFORM_OS
export PLATFORM_ARCH
export PLATFORM_NIX_SYSTEM
export PLATFORM_LINUX_SYSTEM
export PLATFORM_IS_WSL
export PLATFORM_DOCKER_ARCH

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

# Returns Docker server version
platform_docker_version() {
  docker version --format '{{.Server.Version}}' 2>/dev/null || echo "not installed"
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
  echo "  Docker version: $(platform_docker_version)"
  echo "========================"
}

# Mark as loaded
_PLATFORM_LOADED="true"
