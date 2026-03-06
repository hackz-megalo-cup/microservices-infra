#!/usr/bin/env bash
set -euo pipefail

echo "=== Installing Cilium (with Hubble) ==="

# Helm repo
helm repo add cilium https://helm.cilium.io/
helm repo update

# Cilium インストール（Istio 共存設定）
# - cni.exclusive=false: Istio の CNI プラグインとチェーンできるようにする
# - socketLB.hostNamespaceOnly=true: Istio のトラフィックリダイレクションに干渉しない
# - kubeProxyReplacement=false: Istio との安全な共存のため
helm upgrade --install cilium cilium/cilium \
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

# Cilium 起動待ち
echo "=== Waiting for Cilium to be ready ==="
kubectl rollout status -n kube-system ds/cilium --timeout=300s
kubectl rollout status -n kube-system deploy/hubble-relay --timeout=300s
kubectl rollout status -n kube-system deploy/hubble-ui --timeout=300s

echo "=== Cilium + Hubble installation complete ==="
