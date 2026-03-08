#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "${SCRIPT_DIR}/lib/platform.sh"

CLUSTER_NAME="microservice-infra"
MODE="${1:-full}"

_otel_build() {
  if [ "$PLATFORM_OS" = "darwin" ]; then
    echo "==> macOS detected: building OTel Collector image via Docker (${PLATFORM_LINUX_SYSTEM})..."
    docker run --rm \
      -v "${REPO_ROOT}:/workspace" \
      -v nix-store-otel:/nix \
      -w /workspace \
      nixos/nix:latest \
      sh -c "
        git config --global --add safe.directory /workspace && \
        echo 'experimental-features = nix-command flakes' >> /etc/nix/nix.conf && \
        echo 'filter-syscalls = false' >> /etc/nix/nix.conf && \
        nix build .#packages.${PLATFORM_LINUX_SYSTEM}.otel-collector-image && \
        nix run .#packages.${PLATFORM_LINUX_SYSTEM}.otel-collector-image.copyTo -- docker-archive:/workspace/otel-collector-image.tar
      "

    echo "==> Loading OTel Collector image into Docker daemon..."
    docker load < "${REPO_ROOT}/otel-collector-image.tar"
    rm -f "${REPO_ROOT}/otel-collector-image.tar"
  else
    echo "==> Building OTel Collector image (nix) for ${PLATFORM_LINUX_SYSTEM}..."
    nix build "${REPO_ROOT}#packages.${PLATFORM_LINUX_SYSTEM}.otel-collector-image"

    echo "==> Copying OTel Collector image to Docker daemon..."
    nix run "${REPO_ROOT}#packages.${PLATFORM_LINUX_SYSTEM}.otel-collector-image.copyToDockerDaemon"
  fi
}

_otel_load() {
  echo "==> Loading OTel Collector into kind cluster '${CLUSTER_NAME}'..."
  kind load docker-image "otel-collector:latest" --name "${CLUSTER_NAME}"
}

case "$MODE" in
  build)
    _otel_build
    ;;
  load)
    _otel_load
    ;;
  full|*)
    _otel_build
    _otel_load
    ;;
esac

echo "==> Done. OTel Collector image ${MODE} complete."
