---
name: render-commit-push
description: Render nixidy manifests, then create a branch, commit, and push. Use when the user says "/render-commit-push" or asks to render and push nixidy manifests.
---

# Render, Commit, and Push nixidy Manifests

This skill handles the full workflow of rendering nixidy manifests and pushing them to a remote branch.

## Prerequisites

- You must be inside the `microservices-infra` repository (the devenv shell provides all tooling).
- The Nix devenv must be active (provides `gen-manifests` command and nix tooling).

## Steps

### 1. Render manifests

Run the `gen-manifests` command (which internally calls `bash scripts/gen-manifests.sh`):

```bash
gen-manifests
```

If `gen-manifests` is not available in PATH (e.g., outside devenv), fall back to:

```bash
bash scripts/gen-manifests.sh
```

This does the following:
- Runs `nix build` against `nixidyEnvs.local.environmentPackage` to produce `manifests-result/`
- Copies the result into `manifests/` (removes read-only Nix store permissions)
- Removes the ArgoCD self-referencing Application manifest
- Prints a `git diff --stat` of the changes

### 2. Check what changed

Run:

```bash
git diff --stat -- manifests/
git diff --stat -- manifests-result
```

If there are no changes, inform the user that manifests are already up to date and stop here.

### 3. Ask the user for a branch name

Suggest a branch name based on the convention used in CI: `chore/render-manifests`. If the user wants a different name, use that instead.

**Always ask before proceeding.** Do not create branches or commits without explicit user confirmation.

### 4. Create branch (if needed)

```bash
git checkout -b <branch-name>
```

If the branch already exists, ask the user whether to switch to it or create a new one.

### 5. Stage only manifest files

```bash
git add manifests/ manifests-result
```

Do NOT stage unrelated files. Run `git status` to verify only manifest files are staged.

### 6. CRITICAL: Ask before committing

**You MUST ask the user for explicit permission before running `git commit`.**

The user has a strict no-commit-without-asking policy. Show the user:
- The staged files (`git diff --cached --stat`)
- The proposed commit message

Proposed commit message (following the CI convention):

```
chore: render nixidy manifests
```

Only proceed with `git commit` after the user explicitly says yes.

### 7. Push to remote

After the commit (only if the user approved it):

```bash
git push -u origin <branch-name>
```

### 8. Offer to create a PR

After pushing, offer to create a pull request using:

```bash
gh pr create --title "chore: render nixidy manifests" --body "Rendered nixidy manifests via gen-manifests."
```

The CI workflow (`render-manifests` job) normally handles this automatically on main pushes, but this skill is for manual rendering on feature branches.

## Important Notes

- **NEVER commit without asking the user first.** This is a hard requirement.
- The `manifests/` directory is git-tracked but ignored by CI path filters (`paths-ignore: manifests/**`).
- The `manifests-result` symlink points to the Nix store; `manifests/` is the writable copy.
- If `nix build` fails, check `nix-check` first: `nix-check` runs a quick eval to catch Nix expression errors.
- If chart hashes are empty/wrong, suggest running `fix-chart-hash` before re-rendering.
