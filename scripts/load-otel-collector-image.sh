#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/platform.sh
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

# ---------------------------------------------------------------------------
# R2 cache fetch (smart mode)
# ---------------------------------------------------------------------------
R2_BUCKET_URL="${R2_BUCKET_URL:-}"

_compute_otel_hash() {
  shasum -a 256 "${REPO_ROOT}/flake.nix" "${REPO_ROOT}/flake.lock" \
    | shasum -a 256 | cut -d' ' -f1
}

_otel_fetch_r2() {
  # R2 URL 未設定なら即 fail → fallback
  if [[ -z "$R2_BUCKET_URL" ]]; then
    return 1
  fi

  local hash arch url tar_path
  hash="$(_compute_otel_hash)"
  arch="${PLATFORM_LINUX_SYSTEM}"
  url="${R2_BUCKET_URL%/}/${arch}/${hash}.tar"
  tar_path="${REPO_ROOT}/.cache/otel-collector-${hash}.tar"

  # ローカルキャッシュヒット
  if [[ -f "$tar_path" ]]; then
    echo "==> OTel image found in local cache (${hash:0:12}...)" >&2
    echo "$tar_path"
    return 0
  fi

  # R2 から取得
  mkdir -p "${REPO_ROOT}/.cache"
  echo "==> Fetching OTel image from R2 (${arch}/${hash:0:12}...)..." >&2
  if curl -sfL --max-time 30 -o "${tar_path}.tmp" "$url" && [[ -s "${tar_path}.tmp" ]]; then
    mv "${tar_path}.tmp" "$tar_path"
    echo "==> OTel image fetched from R2" >&2
    echo "$tar_path"
    return 0
  fi

  rm -f "${tar_path}.tmp"
  return 1
}

_otel_smart() {
  local tar_path
  if tar_path="$(_otel_fetch_r2)" && [[ -f "$tar_path" ]]; then
    echo "==> Loading OTel image from cache..."
    docker load < "$tar_path"
  else
    echo "==> R2 cache miss or not configured. Building locally..."
    _otel_build
  fi
}

case "$MODE" in
  build)
    _otel_build
    ;;
  load)
    _otel_load
    ;;
  smart)
    _otel_smart
    ;;
  full|*)
    _otel_smart
    _otel_load
    ;;
esac

echo "==> Done. OTel Collector image ${MODE} complete."
