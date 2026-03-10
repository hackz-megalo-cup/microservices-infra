#!/usr/bin/env bash
# Shared CRD pre-installation — ensures monitoring CRDs are established
# before Phase 3 parallel deployment begins.
#
# Requires: REPO_ROOT to be set

[[ -n "${_CRDS_LOADED:-}" ]] && return 0
_CRDS_LOADED=1

# Install Prometheus Operator CRDs and wait for them to be established.
# Safe to call multiple times (kubectl apply is idempotent).
install_monitoring_crds() {
  local crd_dir="${REPO_ROOT}/manifests-result/kube-prometheus-stack"

  local crd_files=("${crd_dir}/CustomResourceDefinition-"*.yaml)
  if [[ ! -f "${crd_files[0]:-}" ]]; then
    echo "WARNING: No monitoring CRDs found in ${crd_dir}, skipping" >&2
    return 0
  fi

  echo "Pre-installing monitoring CRDs..."
  for f in "${crd_dir}/CustomResourceDefinition-"*.yaml; do
    kubectl apply --server-side --force-conflicts -f "$f" 2>/dev/null
  done

  # Wait for the CRDs that other Phase 3 steps depend on
  local crds=(
    servicemonitors.monitoring.coreos.com
    prometheuses.monitoring.coreos.com
    alertmanagers.monitoring.coreos.com
  )
  for crd in "${crds[@]}"; do
    if kubectl get crd "$crd" &>/dev/null; then
      kubectl wait --for=condition=established crd "$crd" --timeout=60s
    fi
  done
  echo "Monitoring CRDs established."
}
