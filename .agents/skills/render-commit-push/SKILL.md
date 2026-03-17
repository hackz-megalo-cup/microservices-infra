---
name: render-commit-push
description: Render nixidy manifests, then create a branch, commit, and push
disable-model-invocation: true
---

# Render, Commit, Push nixidy Manifests

nixidyマニフェストのレンダリングからリモートブランチへのpushまでの全ワークフロー。

## 前提条件

- `microservices-infra` リポジトリ内で実行
- Nix devenv がアクティブ（`gen-manifests` コマンドを提供）

## Step 1: マニフェストレンダリング

```bash
gen-manifests
```

devenv外の場合：
```bash
bash scripts/gen-manifests.sh
```

内部処理：
- `nix build` で `nixidyEnvs.local.environmentPackage` をビルド → `manifests-result/`
- 結果を `manifests/` にコピー（Nix storeの読み取り専用権限を解除）
- ArgoCD自己参照Applicationマニフェストを削除
- `git diff --stat` で変更を表示

## Step 2: 変更確認

```bash
git diff --stat -- manifests/
git diff --stat -- manifests-result
```

変更がなければ「マニフェストは最新」と報告し、ここで終了。

## Step 3: ブランチ名の確認

CI規約に基づき `chore/render-manifests` を提案。ユーザーの希望があればそちらを使用。

**必ずユーザーの確認を取ってから進む。**

## Step 4: ブランチ作成

```bash
git checkout -b <branch-name>
```

既存ブランチの場合、切り替えるか新規作成するかユーザーに確認。

## Step 5: マニフェストファイルのみステージ

```bash
git add manifests/ manifests-result
```

無関係なファイルはステージしない。`git status` で確認。

## Step 6: コミット（要ユーザー承認）

**`git commit` 実行前に必ずユーザーの明示的な許可を得ること。**

ユーザーに提示する情報：
- ステージ済みファイル（`git diff --cached --stat`）
- コミットメッセージ案: `chore: render nixidy manifests`

ユーザーが明示的にyesと言った場合のみコミットを実行。

## Step 7: Push

```bash
git push -u origin <branch-name>
```

## Step 8: PR作成の提案

push後、PR作成を提案：

```bash
gh pr create --title "chore: render nixidy manifests" --body "Rendered nixidy manifests via gen-manifests."
```

## 注意事項

- **ユーザーの確認なしにコミットしないこと。** これは厳格な要件。
- `manifests/` はgit管理下だがCIパスフィルタで除外（`paths-ignore: manifests/**`）。
- `manifests-result` はNix storeへのシンボリックリンク。`manifests/` が書き込み可能なコピー。
- `nix build` 失敗時は `nix-check` で先にNix式のエラーをチェック。
- チャートハッシュが不正な場合は `fix-chart-hash` を先に実行。
