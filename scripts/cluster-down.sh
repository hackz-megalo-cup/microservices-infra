#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="microservice-infra"

if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster '${CLUSTER_NAME}' does not exist."
  exit 0
fi

echo "Deleting kind cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "${CLUSTER_NAME}"
echo "Cluster deleted."
