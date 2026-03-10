---
name: ci-validate
description: Validate CI workflows locally before pushing. Use when the user says "/ci-validate" or asks to check CI, lint workflows, or validate GitHub Actions.
---

# Validate CI Workflows Locally

This skill runs local validation checks that mirror the CI pipeline defined in `.github/workflows/ci.yml`, so issues are caught before pushing.

## Checks to Run

### Check 1: ShellCheck on all scripts

The CI lint job runs:

```bash
shellcheck -x -P SCRIPTDIR scripts/*.sh scripts/lib/*.sh
```

Run exactly this command. The flags mean:
- `-x`: Follow `source` directives
- `-P SCRIPTDIR`: Resolve `SCRIPTDIR` in source paths

**Pass criteria:** Exit code 0, no warnings or errors.

If shellcheck is not installed, tell the user to enter the devenv shell (`direnv allow` or `nix develop`), which provides shellcheck via the git-hooks configuration.

### Check 2: YAML syntax validation of workflow files

Validate all YAML files under `.github/workflows/`:

```bash
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$f" ] && python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "PASS: $f" || echo "FAIL: $f"
done
```

If python3 is not available, try:

```bash
nix-shell -p python3Packages.pyyaml --run 'for f in .github/workflows/*.yml; do python3 -c "import yaml; yaml.safe_load(open(\"$f\"))" && echo "PASS: $f" || echo "FAIL: $f"; done'
```

**Pass criteria:** All workflow files parse without YAML errors.

### Check 3: Nix flake check

The CI lint job runs `nix flake check`. Run it locally:

```bash
nix flake check
```

This validates flake outputs, runs treefmt checks, and catches Nix evaluation errors.

**Pass criteria:** Exit code 0.

### Check 4: Formatting check

The CI lint job runs:

```bash
nix fmt -- --fail-on-change
```

Run this to ensure all files pass the treefmt formatter (configured in `treefmt-programs.nix`).

**Pass criteria:** Exit code 0, no formatting changes needed.

### Check 5: Common CI issues audit

Manually inspect and report on these common issues:

1. **Permissions**: Verify each job has appropriate `permissions` block. The current CI uses:
   - `changes` job: `contents: read`, `pull-requests: read`
   - `render-manifests` job: `contents: write`, `pull-requests: write`
   - Other jobs: inherit default (read-only)

2. **Path filters**: Verify the `dorny/paths-filter` configuration matches actual file paths:
   - `nix` filter: `flake.nix`, `flake.lock`, `**/*.nix`
   - `scripts` filter: `scripts/**`
   - `otel` filter: `otel-collector/**`

3. **Concurrency**: Verify `cancel-in-progress` is set for PR workflows.

4. **Timeout**: Verify all jobs have `timeout-minutes` set (prevents runaway jobs).

5. **Runner references**: Note any non-standard runners (this repo uses `blacksmith-2vcpu-ubuntu-2404` and `blacksmith-2vcpu-ubuntu-2404-arm`).

### Check 6 (Optional): `act` dry run

If the user has `act` installed, offer to run a dry-run:

```bash
act --dryrun pull_request
```

This simulates the workflow without actually executing steps. If `act` is not available, skip this and mention it as an option.

## Output Format

Present results as a summary table:

```
CI Validation Results
=====================
[PASS] ShellCheck           - All scripts pass
[PASS] YAML syntax          - All workflow files valid
[PASS] Nix flake check      - Flake outputs OK
[PASS] Formatting           - No changes needed
[PASS] CI audit             - No issues found
[SKIP] act dry-run          - act not installed
```

For any FAIL, show the specific error output and suggest a fix.

## Important Notes

- Run all checks from the repository root (`/Users/thirdlf03/src/github.com/hackz-megalo-cup/microservices-infra`).
- The devenv shell provides shellcheck, nix, and treefmt. If tools are missing, suggest entering devenv.
- Do NOT push or commit anything. This skill is read-only validation.
