---
name: bootstrap-cycle
description: Run bootstrap test cycles for the Kind cluster. Use when the user says "/bootstrap-cycle" or asks to test bootstrap, run bootstrap, or set up the cluster.
---

# Bootstrap Test Cycle

This skill runs a full bootstrap cycle for the Kind-based Kubernetes cluster and reports on timing and pod health.

## Step 1: Ask which variant to test

Present these options to the user:

| Variant | Command | Description | Expected Time |
|---------|---------|-------------|---------------|
| **fast-dev** | `bootstrap` | kindnetd (no Cilium), single node, warm cluster support | Cold ~120s, Warm: instant |
| **full** | `full-bootstrap` | Cilium + Istio + ArgoCD + 2 workers | Cold ~200s |
| **lite** | `bootstrap-full` | Cilium + Hubble, 1 worker, no Istio/ArgoCD | Cold ~200s |

Additional flags:
- `--clean`: Force cold start (destroys existing cluster, ignores hash cache)
- `bootstrap --full`: Delegates to lite (bootstrap-full) variant

Wait for the user to choose before proceeding.

## Step 2: Run the bootstrap

Execute the chosen command from the repository root. The commands are devenv scripts that delegate to shell scripts:

- `bootstrap` runs `scripts/bootstrap.sh`
- `bootstrap-full` runs `scripts/bootstrap-full.sh`
- `full-bootstrap` runs `scripts/full-bootstrap.sh`

If running outside devenv, use the scripts directly:

```bash
bash scripts/bootstrap.sh        # fast-dev
bash scripts/bootstrap-full.sh   # lite
bash scripts/full-bootstrap.sh   # full
```

Run the command and stream the output. The bootstrap scripts use a 4-phase parallel execution model:

1. **Phase 1 (Preparation)**: kind cluster creation + nix manifest generation + image preload (parallel)
2. **Phase 2 (Network)**: Image loading into kind + Cilium/Istio install (lite/full only)
3. **Phase 3 (Deploy)**: Service deployment -- garage, observability, traefik, redpanda, cloudflared (parallel)
4. **Phase 4 (Wait)**: Wait for all pods to become ready (parallel)

The scripts include built-in timing via `lib/timing.sh` and produce a timing report at the end.

## Step 3: Monitor output

Watch for these key indicators during the run:

- **"Phase N" markers**: Track which phase is currently executing
- **"WARNING"**: Non-fatal issues (e.g., failed image pulls, missing CRDs)
- **"ERROR"**: Fatal issues that need investigation
- **"Waiting for pods"**: Final health-check phase
- **Timing report**: Printed at the end with per-phase breakdown

If the bootstrap uses warm cluster detection (fast-dev and full variants), it may skip phases:
- **"Cluster up-to-date"**: Hash match, quick health check only
- **"Warm reapply"**: Manifests changed, reapply without recreating cluster

## Step 4: Report timing and pod status

After bootstrap completes, run:

```bash
echo "=== Pod Status ==="
kubectl get pods -A
echo ""
echo "=== Node Status ==="
kubectl get nodes -o wide
echo ""
echo "=== Recent Events (last 10) ==="
kubectl get events -A --sort-by=.lastTimestamp | tail -10
```

Or use the built-in debug command:

```bash
debug-k8s
```

Present a summary:
- Total bootstrap time (from the timing report)
- Per-phase breakdown
- Pod count: Ready / Total
- Any pods not in Running/Completed state

## Step 5: Investigate failures automatically

If any pods are not ready, automatically investigate:

### For CrashLoopBackOff / Error pods:

```bash
kubectl logs <pod-name> -n <namespace> --tail=50
kubectl describe pod <pod-name> -n <namespace> | tail -30
```

### For Pending pods:

```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Events:"
kubectl get events -n <namespace> --field-selector involvedObject.name=<pod-name>
```

### For ImagePullBackOff:

```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A3 "Warning"
```

### Common root causes and fixes:

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| PostgreSQL stuck Pending | PVC not bound | Check storage class, restart bootstrap |
| OTel Collector ImagePullBackOff | Custom image not loaded | Run `load-otel-collector-image` |
| Prometheus CRD errors | CRDs not established | Re-run observability step |
| Cilium not ready | CNI conflict with kindnetd | Use `--clean` to start fresh |
| Garage setup fails | Garage pod not ready | Wait and retry `garage-setup.sh` |

Present findings with specific remediation steps.

## Port Access Summary

After a successful bootstrap, remind the user of available services:

| Port | Service | Variants |
|------|---------|----------|
| 30081 | Traefik HTTP | all |
| 30090 | Prometheus | all |
| 30093 | Alertmanager | all |
| 30300 | Grafana (admin/admin) | all |
| 30082 | Redpanda Console | all |
| 31235 | Hubble UI | lite, full |
| 30080 | ArgoCD HTTP | full only |
| 30443 | ArgoCD HTTPS | full only |

## Important Notes

- **Do NOT commit anything.** This skill only runs and monitors bootstrap.
- Bootstrap requires Docker to be running.
- On macOS, ensure Docker Desktop has sufficient resources (recommend 8GB+ RAM for full variant).
- The `--clean` flag is useful when switching between variants or debugging persistent issues.
- Warm cluster detection uses hash files in `.bootstrap-state/` (fast-dev) or `.bootstrap-state-full/` (full).
