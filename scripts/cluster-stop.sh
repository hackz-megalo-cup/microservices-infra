#!/usr/bin/env bash
# Stop kind cluster containers without deleting (preserves state for fast restart)
set -euo pipefail

CLUSTER_NAME="microservice-infra"

readarray -t containers < <(docker ps -q --filter "label=io.x-k8s.kind.cluster=${CLUSTER_NAME}" 2>/dev/null)

if [[ ${#containers[@]} -eq 0 ]]; then
  echo "No running containers for cluster '${CLUSTER_NAME}'."
  exit 0
fi

echo "Stopping kind cluster '${CLUSTER_NAME}'..."
docker stop "${containers[@]}"
echo "Cluster stopped. Use 'cluster-start' to resume."
