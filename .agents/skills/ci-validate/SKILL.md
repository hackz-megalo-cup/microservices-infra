---
name: ci-validate
description: Validate CI workflows locally before pushing. Use when checking CI, linting workflows, or validating GitHub Actions.
---

# CI ローカルバリデーション

`.github/workflows/ci.yml` のCIパイプラインをローカルで検証し、push前に問題を検出する。

## Check 1: ShellCheck

```bash
shellcheck -x -P SCRIPTDIR scripts/*.sh scripts/lib/*.sh
```

- `-x`: `source` ディレクティブを追跡
- `-P SCRIPTDIR`: ソースパスの `SCRIPTDIR` を解決
- **合格条件:** Exit code 0

shellcheck が未インストールの場合、devenv shell への入り方を案内（`direnv allow` or `nix develop`）。

## Check 2: YAML構文検証

```bash
for f in .github/workflows/*.yml .github/workflows/*.yaml; do
  [ -f "$f" ] && python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "PASS: $f" || echo "FAIL: $f"
done
```

**合格条件:** 全ワークフローファイルがYAMLエラーなしでパース。

## Check 3: Nix flake check

```bash
nix flake check
```

**合格条件:** Exit code 0

## Check 4: フォーマットチェック

```bash
nix fmt -- --fail-on-change
```

**合格条件:** Exit code 0、フォーマット変更不要。

## Check 5: CI設定監査

以下を検査・報告：

1. **Permissions**: 各jobに適切な `permissions` ブロックがあるか
2. **Path filters**: `dorny/paths-filter` が実ファイルパスと一致するか
3. **Concurrency**: PR用に `cancel-in-progress` が設定されているか
4. **Timeout**: 全jobに `timeout-minutes` があるか
5. **Runner**: 非標準ランナーの確認（`blacksmith-2vcpu-ubuntu-2404` 等）

## Check 6（任意）: `act` dry run

`act` がインストール済みの場合のみ：

```bash
act --dryrun pull_request
```

未インストールならスキップ。

## 出力フォーマット

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

FAILの場合、具体的なエラー出力と修正案を表示。

## 注意事項

- リポジトリルートから全チェックを実行すること。
- devenv shell が shellcheck, nix, treefmt を提供する。
- **コミット・pushは一切行わない。** 読み取り専用の検証スキル。
