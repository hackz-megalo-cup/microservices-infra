#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"

AGONES_VERSION="${AGONES_VERSION:-1.54.0}"
NAMESPACE="agones-system"

echo "==> Installing Agones ${AGONES_VERSION}..."

# Helm repo add
helm repo add agones https://agones.dev/chart/stable
helm repo update agones

# Install (upgrade if already exists)
helm upgrade --install agones agones/agones \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --version "${AGONES_VERSION}" \
  --set "gameservers.minPort=7000" \
  --set "gameservers.maxPort=7010" \
  --set "agones.controller.replicas=1" \
  --set "agones.extensions.replicas=1" \
  --set "agones.allocator.replicas=1" \
  --set "agones.ping.replicas=1" \
  --wait --timeout 120s

# Remove control-plane taint so GameServer pods can schedule on single node
kubectl taint nodes --all node-role.kubernetes.io/control-plane:NoSchedule- 2>/dev/null || true

echo "==> Agones installed. Verifying..."
kubectl get pods -n "${NAMESPACE}"
