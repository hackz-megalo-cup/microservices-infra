#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/images.sh"

echo "=== Installing Cilium (with Hubble) via OCI chart ==="

# Cilium インストール（Istio 共存設定）
# - cni.exclusive=false: Istio の CNI プラグインとチェーンできるようにする
# - socketLB.hostNamespaceOnly=true: Istio のトラフィックリダイレクションに干渉しない
# - kubeProxyReplacement=false: Istio との安全な共存のため
helm upgrade --install cilium oci://quay.io/cilium/charts/cilium \
  --version "${CILIUM_VERSION}" \
  --namespace kube-system \
  --set image.pullPolicy=IfNotPresent \
  --set ipam.mode=kubernetes \
  --set cni.exclusive=false \
  --set socketLB.hostNamespaceOnly=true \
  --set kubeProxyReplacement=false \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.ui.service.type=NodePort \
  --set hubble.ui.service.nodePort=31235

# Cilium 起動待ち (hubble-relay/hubble-ui are not critical for CNI readiness)
echo "=== Waiting for Cilium DaemonSet to be ready ==="
kubectl rollout status -n kube-system ds/cilium --timeout=300s

echo "=== Cilium installation complete ==="
