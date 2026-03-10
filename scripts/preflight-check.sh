#!/usr/bin/env bash
# scripts/preflight-check.sh — Pre-flight platform compatibility checker
# Checks Docker, kind, ports, architecture, and cluster status before bootstrap.
# Usage: preflight-check.sh
set -euo pipefail

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

CLUSTER_NAME="microservice-infra"

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[0;33m'
_CYAN='\033[0;36m'
_BOLD='\033[1m'
_RESET='\033[0m'

_pass() { printf '  %bPASS%b  %s\n' "$_GREEN" "$_RESET" "$1"; }
_fail() { printf '  %bFAIL%b  %s\n' "$_RED" "$_RESET" "$1"; }
_warn() { printf '  %bWARN%b  %s\n' "$_YELLOW" "$_RESET" "$1"; }
_info() { printf '  %bINFO%b  %s\n' "$_CYAN" "$_RESET" "$1"; }

# ---------------------------------------------------------------------------
# Ports used by kind configs (extracted from k8s/kind-config*.yaml)
# ---------------------------------------------------------------------------
REQUIRED_PORTS=(30080 30443 30300 30081 30444 31235 30090 30093 30082)

# ---------------------------------------------------------------------------
# Check functions
# ---------------------------------------------------------------------------
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0

_check() {
  TOTAL_CHECKS=$(( TOTAL_CHECKS + 1 ))
}

_mark_pass() {
  PASSED_CHECKS=$(( PASSED_CHECKS + 1 ))
}

_mark_fail() {
  FAILED_CHECKS=$(( FAILED_CHECKS + 1 ))
}

# ---------------------------------------------------------------------------
# 1. CPU Architecture
# ---------------------------------------------------------------------------
check_architecture() {
  _check
  local raw_arch
  raw_arch="$(uname -m)"
  case "$raw_arch" in
    arm64|aarch64)
      _pass "CPU architecture: ${raw_arch} (arm64)"
      _mark_pass
      ;;
    x86_64|amd64)
      _pass "CPU architecture: ${raw_arch} (amd64)"
      _mark_pass
      ;;
    *)
      _fail "Unsupported CPU architecture: ${raw_arch}"
      _mark_fail
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 2. Rosetta emulation status (macOS only)
# ---------------------------------------------------------------------------
check_rosetta() {
  _check
  if [[ "$PLATFORM_OS" != "darwin" ]]; then
    _info "Rosetta check: skipped (not macOS)"
    _mark_pass
    return
  fi

  if [[ "$PLATFORM_ARCH" == "aarch64" ]]; then
    # Check if Rosetta is installed
    if /usr/bin/pgrep -q oahd 2>/dev/null; then
      _pass "Rosetta 2 is installed and running (not required, but available)"
    else
      _info "Rosetta 2 is not active (expected for native arm64)"
    fi
    _mark_pass
  else
    # Running x86_64 binary on macOS — might be under Rosetta
    if sysctl -n sysctl.proc_translated 2>/dev/null | grep -q "1"; then
      _warn "Running under Rosetta emulation — native arm64 is recommended"
    else
      _pass "Running native x86_64"
    fi
    _mark_pass
  fi
}

# ---------------------------------------------------------------------------
# 3. Docker runtime detection
# ---------------------------------------------------------------------------
check_docker_installed() {
  _check
  if ! command -v docker &>/dev/null; then
    _fail "Docker is not installed or not in PATH"
    _mark_fail
    return 1
  fi
  _pass "Docker is installed"
  _mark_pass
  return 0
}

check_docker_running() {
  _check
  if ! docker info &>/dev/null; then
    _fail "Docker daemon is not running"
    _mark_fail
    return 1
  fi
  _pass "Docker daemon is running"
  _mark_pass
  return 0
}

check_docker_runtime() {
  _check
  case "$PLATFORM_DOCKER_RUNTIME" in
    orbstack)
      _pass "Docker runtime: OrbStack (recommended)"
      _mark_pass
      ;;
    docker-desktop)
      _warn "Docker runtime: Docker Desktop (OrbStack is recommended for macOS)"
      _mark_pass

      # Check Docker Desktop resources
      local docker_mem_gb docker_cpus
      docker_mem_gb="$(platform_docker_memory_gb)"
      docker_cpus="$(platform_docker_cpus)"

      _check
      if [[ "$docker_mem_gb" -gt 0 ]] && [[ "$docker_mem_gb" -lt 8 ]]; then
        _fail "Docker Desktop memory: ${docker_mem_gb}GB (minimum 8GB recommended)"
        _mark_fail
      else
        _pass "Docker Desktop memory: ${docker_mem_gb}GB"
        _mark_pass
      fi

      _check
      if [[ "$docker_cpus" -gt 0 ]] && [[ "$docker_cpus" -lt 4 ]]; then
        _fail "Docker Desktop CPUs: ${docker_cpus} (minimum 4 recommended)"
        _mark_fail
      else
        _pass "Docker Desktop CPUs: ${docker_cpus}"
        _mark_pass
      fi
      ;;
    other)
      _info "Docker runtime: other (not OrbStack or Docker Desktop)"
      _mark_pass
      ;;
    none)
      _fail "Docker runtime: not detected"
      _mark_fail
      ;;
    *)
      _warn "Docker runtime: unknown (${PLATFORM_DOCKER_RUNTIME})"
      _mark_pass
      ;;
  esac
}

# ---------------------------------------------------------------------------
# 4. kind installation
# ---------------------------------------------------------------------------
check_kind() {
  _check
  if ! command -v kind &>/dev/null; then
    _fail "kind is not installed or not in PATH"
    _mark_fail
    return
  fi
  local kind_version
  kind_version="$(kind version 2>/dev/null || echo "unknown")"
  _pass "kind is installed (${kind_version})"
  _mark_pass
}

# ---------------------------------------------------------------------------
# 5. kubectl installation
# ---------------------------------------------------------------------------
check_kubectl() {
  _check
  if ! command -v kubectl &>/dev/null; then
    _fail "kubectl is not installed or not in PATH"
    _mark_fail
    return
  fi
  _pass "kubectl is installed"
  _mark_pass
}

# ---------------------------------------------------------------------------
# 6. Port availability
# ---------------------------------------------------------------------------
check_ports() {
  local all_free="true"
  for port in "${REQUIRED_PORTS[@]}"; do
    _check
    # Use lsof to check if port is in use on 127.0.0.1
    if lsof -iTCP:"${port}" -sTCP:LISTEN -P -n &>/dev/null; then
      _fail "Port ${port} is already in use"
      _mark_fail
      all_free="false"
    else
      _pass "Port ${port} is available"
      _mark_pass
    fi
  done

  if [[ "$all_free" != "true" ]]; then
    echo ""
    _warn "Some ports are in use. This may cause issues with kind port mappings."
    _warn "Check which process is using the port: lsof -iTCP:<port> -sTCP:LISTEN"
  fi
}

# ---------------------------------------------------------------------------
# 7. Existing kind cluster
# ---------------------------------------------------------------------------
check_existing_cluster() {
  _check
  if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
    _info "Kind cluster '${CLUSTER_NAME}' already exists"
    _mark_pass

    # Check if it's healthy
    _check
    if kubectl cluster-info --context "kind-${CLUSTER_NAME}" &>/dev/null; then
      _pass "Existing cluster is reachable"
      _mark_pass
    else
      _warn "Existing cluster is not reachable (may need restart or deletion)"
      _mark_pass
    fi
  else
    _info "No existing kind cluster '${CLUSTER_NAME}'"
    _mark_pass
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
printf '%b=== Pre-flight Compatibility Check ===%b\n' "$_BOLD" "$_RESET"
echo ""

printf '%bPlatform%b\n' "$_BOLD" "$_RESET"
check_architecture
check_rosetta
echo ""

printf '%bDocker%b\n' "$_BOLD" "$_RESET"
docker_ok="true"
check_docker_installed || docker_ok="false"
if [[ "$docker_ok" == "true" ]]; then
  check_docker_running || docker_ok="false"
fi
if [[ "$docker_ok" == "true" ]]; then
  check_docker_runtime
fi
echo ""

printf '%bTools%b\n' "$_BOLD" "$_RESET"
check_kind
check_kubectl
echo ""

printf '%bPort Availability%b\n' "$_BOLD" "$_RESET"
check_ports
echo ""

printf '%bCluster Status%b\n' "$_BOLD" "$_RESET"
check_existing_cluster
echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '%b=== Summary ===%b\n' "$_BOLD" "$_RESET"
printf "  Total checks:  %d\n" "$TOTAL_CHECKS"
printf '  %bPassed:        %d%b\n' "$_GREEN" "$PASSED_CHECKS" "$_RESET"
printf '  %bFailed:        %d%b\n' "$_RED" "$FAILED_CHECKS" "$_RESET"
echo ""

if [[ "$FAILED_CHECKS" -gt 0 ]]; then
  printf '%b%bPre-flight check FAILED — resolve the issues above before bootstrapping.%b\n' "$_RED" "$_BOLD" "$_RESET"
  echo ""
  exit 1
else
  printf '%b%bPre-flight check PASSED — ready to bootstrap.%b\n' "$_GREEN" "$_BOLD" "$_RESET"
  echo ""
  exit 0
fi
