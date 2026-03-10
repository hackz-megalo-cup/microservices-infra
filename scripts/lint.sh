#!/usr/bin/env bash
# scripts/lint.sh — Local linting script that mirrors CI checks
# Runs shellcheck, nix flake check, and formatting verification.
# Usage: lint.sh [--fix]
set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
_RED='\033[0;31m'
_GREEN='\033[0;32m'
_YELLOW='\033[0;33m'
_BOLD='\033[1m'
_RESET='\033[0m'

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Local linting script — mirrors CI checks locally.

Options:
  --fix    Auto-fix formatting issues (runs 'nix fmt' without --fail-on-change)
  --help   Show this help message

Checks performed (matching CI):
  1. shellcheck — lint all shell scripts (scripts/*.sh scripts/lib/*.sh)
  2. nix flake check — evaluate nix expressions
  3. nix fmt — verify formatting (nixfmt, deadnix, statix)
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
FIX_MODE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fix)
      FIX_MODE="true"
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo "Error: unknown argument '$1'" >&2
      echo "Run '$(basename "$0") --help' for usage." >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# State tracking
# ---------------------------------------------------------------------------
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
FAILED_NAMES=()

run_check() {
  local name="$1"
  shift
  TOTAL_CHECKS=$(( TOTAL_CHECKS + 1 ))

  printf '%b>>> [%s]%b %s\n' "$_BOLD" "$name" "$_RESET" "$*"
  echo ""

  if "$@"; then
    printf '\n%b<<< [%s] PASSED%b\n\n' "$_GREEN" "$name" "$_RESET"
    PASSED_CHECKS=$(( PASSED_CHECKS + 1 ))
  else
    printf '\n%b<<< [%s] FAILED%b\n\n' "$_RED" "$name" "$_RESET"
    FAILED_CHECKS=$(( FAILED_CHECKS + 1 ))
    FAILED_NAMES+=("$name")
  fi
}

# ---------------------------------------------------------------------------
# Check: shellcheck
# ---------------------------------------------------------------------------
# shellcheck disable=SC2317,SC2329
check_shellcheck() {
  if ! command -v shellcheck &>/dev/null; then
    echo "WARNING: shellcheck not found in PATH, skipping" >&2
    echo "Install via: nix-shell -p shellcheck (or enter devenv shell)" >&2
    return 1
  fi

  # Match CI: shellcheck -x -P SCRIPTDIR scripts/*.sh scripts/lib/*.sh
  local shell_scripts=()
  for f in "${REPO_ROOT}"/scripts/*.sh "${REPO_ROOT}"/scripts/lib/*.sh; do
    [[ -f "$f" ]] && shell_scripts+=("$f")
  done

  if [[ ${#shell_scripts[@]} -eq 0 ]]; then
    echo "No shell scripts found to check."
    return 0
  fi

  shellcheck -x -P SCRIPTDIR "${shell_scripts[@]}"
}

# ---------------------------------------------------------------------------
# Check: nix flake check
# ---------------------------------------------------------------------------
# shellcheck disable=SC2317,SC2329
check_nix_flake() {
  if ! command -v nix &>/dev/null; then
    echo "WARNING: nix not found in PATH, skipping" >&2
    return 1
  fi

  cd "$REPO_ROOT"
  nix flake check
}

# ---------------------------------------------------------------------------
# Check: nix fmt (formatting)
# ---------------------------------------------------------------------------
# shellcheck disable=SC2317,SC2329
check_nix_fmt() {
  if ! command -v nix &>/dev/null; then
    echo "WARNING: nix not found in PATH, skipping" >&2
    return 1
  fi

  cd "$REPO_ROOT"
  if [[ "$FIX_MODE" == "true" ]]; then
    echo "(--fix mode: applying formatting fixes)"
    nix fmt
  else
    nix fmt -- --fail-on-change
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo ""
printf '%b=== Local Lint (mirrors CI) ===%b\n' "$_BOLD" "$_RESET"
echo ""

run_check "shellcheck" check_shellcheck
run_check "nix-flake-check" check_nix_flake
run_check "nix-fmt" check_nix_fmt

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '%b=== Lint Summary ===%b\n' "$_BOLD" "$_RESET"
printf "  Total:   %d\n" "$TOTAL_CHECKS"
printf '  %bPassed:  %d%b\n' "$_GREEN" "$PASSED_CHECKS" "$_RESET"
printf '  %bFailed:  %d%b\n' "$_RED" "$FAILED_CHECKS" "$_RESET"

if [[ "$FAILED_CHECKS" -gt 0 ]]; then
  echo ""
  printf '  %bFailed checks:%b\n' "$_RED" "$_RESET"
  for name in "${FAILED_NAMES[@]}"; do
    printf "    - %s\n" "$name"
  done
  echo ""
  printf '%b%bLint FAILED%b\n' "$_RED" "$_BOLD" "$_RESET"
  echo ""
  exit 1
else
  echo ""
  printf '%b%bLint PASSED%b\n' "$_GREEN" "$_BOLD" "$_RESET"
  echo ""
  exit 0
fi
