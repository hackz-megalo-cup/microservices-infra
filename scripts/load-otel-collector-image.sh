#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

CLUSTER_NAME="microservice-infra"

echo "==> Building OTel Collector image (nix)..."
nix build "${REPO_ROOT}#otel-collector-image"

echo "==> Copying OTel Collector image to Docker daemon..."
nix run "${REPO_ROOT}#otel-collector-image.copyToDockerDaemon"

echo "==> Loading OTel Collector into kind cluster '${CLUSTER_NAME}'..."
kind load docker-image "otel-collector:latest" --name "${CLUSTER_NAME}"

echo "==> Done. OTel Collector image loaded."
