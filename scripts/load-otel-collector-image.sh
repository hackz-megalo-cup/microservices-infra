#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

CLUSTER_NAME="microservice-infra"

if [ "$(uname -s)" = "Darwin" ]; then
  # Map macOS arch to Nix system string
  ARCH="$(uname -m)"
  case "$ARCH" in
    arm64) ARCH="aarch64" ;;
  esac
  LINUX_SYSTEM="${ARCH}-linux"

  echo "==> macOS detected: building OTel Collector image via Docker (${LINUX_SYSTEM})..."
  docker run --rm \
    -v "${REPO_ROOT}:/workspace" \
    -v nix-store-otel:/nix \
    -w /workspace \
    nixos/nix:latest \
    sh -c "
      git config --global --add safe.directory /workspace && \
      echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf && \
      echo 'filter-syscalls = false' >> /etc/nix/nix.conf && \
      nix build .#packages.${LINUX_SYSTEM}.otel-collector-image && \
      nix run .#packages.${LINUX_SYSTEM}.otel-collector-image.copyTo -- docker-archive:/workspace/otel-collector-image.tar
    "

  echo "==> Loading OTel Collector image into Docker daemon..."
  docker load < "${REPO_ROOT}/otel-collector-image.tar"
  rm -f "${REPO_ROOT}/otel-collector-image.tar"
else
  echo "==> Building OTel Collector image (nix)..."
  nix build "${REPO_ROOT}#otel-collector-image"

  echo "==> Copying OTel Collector image to Docker daemon..."
  nix run "${REPO_ROOT}#otel-collector-image.copyToDockerDaemon"
fi

echo "==> Loading OTel Collector into kind cluster '${CLUSTER_NAME}'..."
kind load docker-image "otel-collector:latest" --name "${CLUSTER_NAME}"

echo "==> Done. OTel Collector image loaded."
