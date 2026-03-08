#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

CLUSTER_NAME="microservice-infra"

if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' already exists."
  kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
  kubectl cluster-info --context "kind-${CLUSTER_NAME}"
  exit 0
fi

echo "Creating kind cluster '${CLUSTER_NAME}'..."
kind create cluster --config "${REPO_ROOT}/k8s/kind-config.yaml"
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true

echo "Cluster created. Context set to kind-${CLUSTER_NAME}."
kubectl cluster-info --context "kind-${CLUSTER_NAME}"
