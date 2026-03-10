#!/usr/bin/env bash
# scripts/lib/images.sh — Container image lists for pre-loading into kind clusters
# Source this file to set PRELOAD_IMAGES and PRELOAD_IMAGES_FULL arrays.
# Safe to source multiple times (idempotent via guard variable).

# Idempotency guard
if [[ "${_IMAGES_LOADED:-}" == "true" ]]; then
  return 0
fi

# ---------------------------------------------------------------------------
# Version pins
# ---------------------------------------------------------------------------
CILIUM_VERSION="1.19.1"

# ---------------------------------------------------------------------------
# Base images — used by bootstrap.sh and cilium-install.sh
# ---------------------------------------------------------------------------
PRELOAD_IMAGES=(
  "quay.io/cilium/cilium:v${CILIUM_VERSION}"
  "registry-1.docker.io/bitnami/postgresql:latest"
  "docker.io/grafana/grafana:12.4.0"
  "quay.io/prometheus/prometheus:v3.10.0"
  "docker.io/grafana/loki:3.6.5"
  "docker.io/grafana/tempo:2.9.0"
  "docker.io/traefik:v3.6.9"
  "dxflrs/garage:v1.1.0"
  "docker.redpanda.com/redpandadata/redpanda:v25.3.10"
)

# ---------------------------------------------------------------------------
# Full images — base + ArgoCD stack, used by full-bootstrap.sh
# ---------------------------------------------------------------------------
export PRELOAD_IMAGES_FULL
PRELOAD_IMAGES_FULL=(
  "${PRELOAD_IMAGES[@]}"
  "quay.io/argoproj/argocd:v3.3.2"
  "ecr-public.aws.com/docker/library/redis:8.2.3-alpine"
)

# ---------------------------------------------------------------------------
# Dev images — no Cilium, OTel is fetched from R2 separately
# ---------------------------------------------------------------------------
export PRELOAD_IMAGES_DEV
PRELOAD_IMAGES_DEV=(
  "registry-1.docker.io/bitnami/postgresql:latest"
  "docker.io/grafana/grafana:12.4.0"
  "quay.io/prometheus/prometheus:v3.10.0"
  "docker.io/grafana/loki:3.6.5"
  "docker.io/grafana/tempo:2.9.0"
  "docker.io/traefik:v3.6.9"
  "dxflrs/garage:v1.1.0"
  "docker.redpanda.com/redpandadata/redpanda:v25.3.10"
)

# Mark as loaded
_IMAGES_LOADED="true"
