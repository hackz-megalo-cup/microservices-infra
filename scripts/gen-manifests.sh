#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"

echo "==> Building nixidy manifests..."
nix build "${REPO_ROOT}#legacyPackages.${PLATFORM_NIX_SYSTEM}.nixidyEnvs.local.environmentPackage" -o "${REPO_ROOT}/manifests-result"

echo "==> Copying to manifests/..."
rm -rf "${REPO_ROOT}/manifests"
cp -rL "${REPO_ROOT}/manifests-result" "${REPO_ROOT}/manifests"
chmod -R u+w "${REPO_ROOT}/manifests"

rm -f "${REPO_ROOT}/manifests/apps/Application-argocd.yaml"

echo "==> Done. manifests/ updated."
echo ""
git -C "${REPO_ROOT}" --no-pager diff --stat -- manifests/
