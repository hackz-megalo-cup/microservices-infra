#!/usr/bin/env bash
# Start previously stopped kind cluster containers
set -euo pipefail

CLUSTER_NAME="microservice-infra"

containers=$(docker ps -aq --filter "label=io.x-k8s.kind.cluster=${CLUSTER_NAME}" 2>/dev/null)

if [[ -z "$containers" ]]; then
  echo "No containers found for cluster '${CLUSTER_NAME}'. Run 'bootstrap' first."
  exit 1
fi

running=$(docker ps -q --filter "label=io.x-k8s.kind.cluster=${CLUSTER_NAME}" 2>/dev/null)
if [[ -n "$running" ]]; then
  echo "Cluster '${CLUSTER_NAME}' is already running."
  kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
  exit 0
fi

echo "Starting kind cluster '${CLUSTER_NAME}'..."
docker start $containers

echo "Waiting for API server..."
until kubectl cluster-info --context "kind-${CLUSTER_NAME}" &>/dev/null; do
  sleep 1
done

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true
echo "Cluster started."
kubectl get nodes
