# ブートストラップモード

## モード比較

| | Dev-fast (`bootstrap`) | Cilium (`bootstrap-full`) | Full (`full-bootstrap`) |
|---|---|---|---|
| CNI | kindnetd | Cilium + Hubble | Cilium + Hubble |
| ノード | control-plane × 1 | control-plane + worker × 1 | control-plane + worker × 2 |
| Istio | なし | なし | ambient mode |
| ArgoCD | なし | なし | あり |
| Warm cluster | あり | なし | なし |
| Cold start | ~120s | ~200s | ~250s |
| Warm start | 即時 (hash一致) / 10-15s (manifest変更) | — | — |
| 用途 | 日常開発 | CNI テスト | フルスタック検証 |

## Dev-fast モード詳細

### 4 Phase 並列実行

```
Phase 1 (並列): kind create + gen-manifests + OTel fetch + image pull
Phase 2 (逐次): image load into kind
Phase 2.5:      PostgreSQL early start
Phase 3 (並列): garage + observability + traefik + cloudflared deploy
Phase 4 (並列): pod ready 待ち (postgresql, grafana, prometheus)
```

### Warm Cluster (Hash Gate)

- `.bootstrap-state/cluster` — kind config + images.sh の SHA-256 hash
- `.bootstrap-state/manifest` — manifests-result/ 全体の SHA-256 hash
- クラスタ起動中 + cluster hash 一致 + manifest hash 一致 → health check のみ (即完了)
- クラスタ起動中 + cluster hash 一致 + manifest hash 不一致 → warm reapply (manifest 再適用)
- cluster hash 不一致 or クラスタ停止 → cold start (フルリビルド)

### フラグ

- `bootstrap --clean` — 既存クラスタ削除 + cold start
- `bootstrap --full` — `bootstrap-full.sh` に委譲 (Cilium モード)

## クラスタ管理コマンド

| コマンド | 動作 | 用途 |
|---|---|---|
| `cluster-stop` | Docker コンテナ停止 (状態保持) | PC 再起動前、リソース節約 |
| `cluster-start` | 停止コンテナ再開 | 作業再開時 |
| `cluster-down` | クラスタ完全削除 | リセット |

## 使用スクリプト

### メインスクリプト

| スクリプト | 説明 |
|---|---|
| `scripts/bootstrap.sh` | Dev-fast ブートストラップ (warm cluster 対応) |
| `scripts/bootstrap-full.sh` | Cilium モードブートストラップ |
| `scripts/full-bootstrap.sh` | フルスタックブートストラップ |
| `scripts/cluster-stop.sh` | クラスタ停止 |
| `scripts/cluster-start.sh` | クラスタ再開 |
| `scripts/benchmark.sh` | ベンチマーク実行 |

### ライブラリ (`scripts/lib/`)

| ファイル | 説明 |
|---|---|
| `platform.sh` | プラットフォーム検出 (OS, arch, Docker arch, WSL) |
| `timing.sh` | Phase 計測・レポート |
| `parallel.sh` | 並列タスク実行 |
| `monitor.sh` | CPU/メモリ使用率モニタリング |
| `images.sh` | コンテナイメージリスト (PRELOAD_IMAGES, PRELOAD_IMAGES_FULL, PRELOAD_IMAGES_DEV) |

### OTel Collector イメージ

`scripts/load-otel-collector-image.sh` — 3つのモード:

| モード | 動作 |
|---|---|
| `build` | Nix でローカルビルド |
| `load` | Docker → kind にロード |
| `smart` | R2 キャッシュ → ローカルキャッシュ → ビルド (フォールバック) |
| `full` | smart + load |

### R2 OTel キャッシュ

CI (`.github/workflows/ci.yml` の `build-otel-image` ジョブ) が main push 時に:
1. `flake.nix` + `flake.lock` の hash を計算
2. R2 にキャッシュがなければ Nix ビルド (x86_64-linux, aarch64-linux)
3. `s3://microservices-infra-cache/otel-collector/{arch}/{hash}.tar` にアップロード

ローカルの `bootstrap.sh` は `R2_BUCKET_URL` 環境変数経由で R2 からフェッチ。devenv.nix で自動設定済み。

## ベンチマーク

```bash
benchmark 3   # 3回実行して統計表示
```

結果は `logs/benchmark/` に JSON で保存。Phase 別の平均・中央値・標準偏差・CPU/メモリ使用率を表示。

### 実測値 (Apple M4, 24GB)

| Phase | 時間 |
|---|---|
| phase1-prep | ~12s |
| phase2-load | ~37s |
| phase3-deploy | ~21s |
| phase4-wait | ~52s |
| **TOTAL** | **~122s** |

従来の Cilium モード (~197s) から **38% 短縮**。
