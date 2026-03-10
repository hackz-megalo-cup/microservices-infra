# CLAUDE.md — microservices-infra

## Project Overview

Local Kubernetes (Kind) infrastructure platform for a microservices system. Uses **nixidy** (Nix + Kustomize) to declaratively generate K8s manifests from Nix expressions, then applies them to a Kind cluster.

**Stack:** Kind / Cilium / Istio (ambient) / ArgoCD / Traefik / Prometheus + Grafana + Loki + Tempo / OTel Collector / Garage (S3-compatible) / Redpanda (Kafka-compatible) / PostgreSQL

**Dev environment:** Nix flakes + devenv + direnv. `direnv allow` auto-loads all CLI tools (kubectl, kind, helm, cilium-cli, argocd, etc.).

## Key Commands

### Bootstrap variants

| Command | Mode | Use when |
|---|---|---|
| `bootstrap` | Dev-fast: kindnetd, single node, warm cluster | Day-to-day development (recommended) |
| `bootstrap --clean` | Dev-fast with forced full rebuild | Config is stale or cluster is broken |
| `bootstrap --full` | Delegates to `bootstrap-full` (Cilium) | Need CNI testing |
| `bootstrap-full` | Cilium + Hubble, 1 worker | Testing Cilium-specific features |
| `full-bootstrap` | Cilium + Istio + ArgoCD, 2 workers | Full stack / production parity |

Warm cluster: after first run, `bootstrap` and `full-bootstrap` compare hashes and skip unchanged steps. Use `--clean` to force rebuild.

### Manifest generation

```bash
gen-manifests          # Build nixidy manifests -> manifests-result/ (symlink) + manifests/ (copy)
watch-manifests        # Watch *.nix changes, rebuild + kubectl apply automatically
nix-check              # Fast nix eval sanity check (no cluster needed)
```

- `manifests-result/` is a Nix store symlink (read-only)
- `manifests/` is a writable copy used by kubectl apply and git

### Shellcheck (local)

```bash
shellcheck -x -P SCRIPTDIR scripts/*.sh scripts/lib/*.sh
```

This is the same command CI runs. The `-x` flag follows `source` directives and `-P SCRIPTDIR` resolves relative paths from each script's directory.

### Other useful commands

```bash
cluster-up / cluster-down      # Create / destroy Kind cluster
cluster-stop / cluster-start   # Pause / resume (preserves state)
cilium-install                  # Install Cilium + Hubble
istio-install                   # Install Istio ambient mode
argocd-bootstrap                # Bootstrap ArgoCD
cloudflared-setup               # Cloudflare Tunnel + DNS
debug-k8s                       # Quick pod status + recent events
```

## Docker Compatibility

### OrbStack vs Docker Desktop

- **OrbStack** (recommended): Works out of the box, dynamic memory allocation.
- **Docker Desktop**: Requires manual resource allocation (min 8 GB RAM, 4 CPUs). Disable Docker Desktop's built-in Kubernetes (port conflicts). The bootstrap script detects Docker Desktop and warns about resource limits.

### Port binding

All Kind `extraPortMappings` use `listenAddress: "127.0.0.1"` (localhost only). Key ports: Traefik 30081, Prometheus 30090, Grafana 30300, Redpanda Console 30082, Hubble UI 31235, ArgoCD 30080/30443.

### Architecture detection

`scripts/lib/platform.sh` normalizes `uname -m` to Nix naming (`arm64` -> `aarch64`, `x86_64` stays). The `PLATFORM_NIX_SYSTEM` variable (e.g. `aarch64-darwin`) is used throughout for Nix builds. OTel Collector images are cross-compiled to the corresponding Linux arch.

## CI Workflow

CI runs on PRs and pushes to main (`.github/workflows/ci.yml`). Path filtering skips jobs when only `manifests/` changes.

### What CI checks (lint job, PRs only)

1. `nix flake check` -- evaluates the flake
2. `shellcheck -x -P SCRIPTDIR scripts/*.sh scripts/lib/*.sh` -- lints all shell scripts
3. `nix fmt -- --fail-on-change` -- checks Nix formatting (nixfmt, deadnix, statix via treefmt)

### What CI does on push to main

1. **render-manifests** -- runs `gen-manifests` and opens a PR with updated `manifests/`
2. **build-otel-image** -- builds OTel Collector for x86_64/aarch64 and caches to R2 (only if hash changed)

### Validate locally before pushing

```bash
shellcheck -x -P SCRIPTDIR scripts/*.sh scripts/lib/*.sh   # Shell lint
nix fmt -- --fail-on-change                                  # Nix format check
nix flake check                                              # Nix evaluation
```

## nixidy Workflow

### How to add a new module

1. Create `nixidy/env/local/<component>.nix` with the module definition
2. Add the import to `nixidy/env/local.nix` (the imports list)
3. Run `gen-manifests` to render
4. Verify output in `manifests-result/<component>/`

### How to render manifests

```bash
gen-manifests
# Internally runs: nix build .#legacyPackages.<system>.nixidyEnvs.local.environmentPackage
```

### Where manifests are output

- `manifests-result/` -- Nix store symlink (source of truth, read-only)
- `manifests/` -- writable copy (this is what gets committed and applied)

## Conventions

### Script conventions

- All scripts start with `set -euo pipefail`
- Source shared libraries: `source "${SCRIPT_DIR}/lib/platform.sh"` (with `# shellcheck source=` directives)
- Use `SCRIPT_DIR` / `REPO_ROOT` for path resolution
- Library scripts use idempotency guards (`_PLATFORM_LOADED`)

### Commit message format

Conventional commits: `feat:`, `fix:`, `chore:`, `ci:`, `docs:`, etc.

### Critical rules

- **NEVER commit without explicit user approval**
- **NEVER run destructive git operations** (force push, reset --hard) without explicit request
- Secrets are managed with SOPS + age (`secrets/` directory) -- never commit plaintext secrets
