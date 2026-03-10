#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# shellcheck source=lib/platform.sh
source "${SCRIPT_DIR}/lib/platform.sh"

CLUSTER_NAME="microservice-infra"
MODE="${1:-full}"
IMAGE_NAME="otel-collector:latest"

# docker load + ensure the image is tagged as otel-collector:latest
# nix2container's copyTo docker-archive may omit RepoTags, resulting in
# an untagged image that kind cannot find.
_docker_load_and_tag() {
  local output
  output="$(docker load < "$1")"
  echo "$output"
  if echo "$output" | grep -q "Loaded image ID:"; then
    local image_id
    image_id="$(echo "$output" | grep -oE 'sha256:[a-f0-9]+')"
    docker tag "$image_id" "$IMAGE_NAME"
    echo "==> Tagged ${image_id} as ${IMAGE_NAME}"
  fi
}

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
    _docker_load_and_tag "${REPO_ROOT}/otel-collector-image.tar"
    rm -f "${REPO_ROOT}/otel-collector-image.tar"
  else
    echo "==> Building OTel Collector image (nix) for ${PLATFORM_LINUX_SYSTEM}..."
    nix build "${REPO_ROOT}#packages.${PLATFORM_LINUX_SYSTEM}.otel-collector-image"

    echo "==> Copying OTel Collector image to Docker daemon..."
    nix run "${REPO_ROOT}#packages.${PLATFORM_LINUX_SYSTEM}.otel-collector-image.copyToDockerDaemon"

    # Safety check: verify the image is tagged after copyToDockerDaemon
    if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
      echo "==> WARNING: copyToDockerDaemon did not tag image as ${IMAGE_NAME}, attempting manual tag..."
      local latest_id
      latest_id="$(docker images --no-trunc --format '{{.ID}} {{.CreatedAt}}' | sort -k2 -r | head -1 | awk '{print $1}')"
      if [[ -n "$latest_id" ]]; then
        docker tag "$latest_id" "$IMAGE_NAME"
        echo "==> Tagged ${latest_id} as ${IMAGE_NAME}"
      else
        echo "==> ERROR: Could not find image to tag" >&2
        return 1
      fi
    fi
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
  (cd "$REPO_ROOT" && shasum -a 256 flake.nix flake.lock) \
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
    _docker_load_and_tag "$tar_path"
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
