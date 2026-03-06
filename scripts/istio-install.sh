#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Installing Gateway API CRDs ==="
kubectl apply --server-side=true -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.0/standard-install.yaml

echo "=== Installing Istio (ambient profile) ==="
istioctl install --set profile=ambient --skip-confirmation \
  --set meshConfig.enableTracing=true \
  --set "meshConfig.extensionProviders[0].name=otel-tracing" \
  --set "meshConfig.extensionProviders[0].opentelemetry.service=otel-collector.observability.svc.cluster.local" \
  --set "meshConfig.extensionProviders[0].opentelemetry.port=4317"

echo "=== Ensuring microservices namespace ==="
kubectl create namespace microservices --dry-run=client -o yaml | kubectl apply -f -

echo "=== Labeling namespace for ambient mode ==="
kubectl label namespace microservices istio.io/dataplane-mode=ambient --overwrite

echo "=== Deploying waypoint proxy ==="
istioctl waypoint apply -n microservices --enroll-namespace --wait

echo "=== Applying Istio CRs ==="
kubectl apply -f "$REPO_ROOT/istio/"

echo "=== Istio ambient setup complete ==="
