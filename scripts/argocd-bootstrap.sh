#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"

echo "Building nixidy manifests..."
nix build "${REPO_ROOT}#legacyPackages.${PLATFORM_NIX_SYSTEM}.nixidyEnvs.local.environmentPackage" -o "${REPO_ROOT}/manifests-result"

echo "Creating argocd namespace..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

echo "Applying ArgoCD manifests to cluster (server-side apply)..."
kubectl apply -f "${REPO_ROOT}/manifests-result/argocd/" --server-side --force-conflicts

echo "Waiting for ArgoCD server to be ready..."
kubectl wait --for=condition=available deployment/argocd-server -n argocd --timeout=300s

echo ""
echo "ArgoCD initial admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo ""
echo ""
echo "ArgoCD UI: http://localhost:30080"
echo "Login with username 'admin' and the password above."
