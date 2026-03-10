# microservice-infra

[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/hackz-megalo-cup/microservices-infra)
[![Mintlify Docs](https://img.shields.io/badge/docs-Mintlify-0ea5e9?logo=mintlify&logoColor=white)](https://mintlify.com/hackz-megalo-cup/microservices-infra)

マイクロサービス基盤のインフラ定義リポジトリ。Kind クラスタ上に監視・ネットワーク・GitOps スタックを構築する。

## アーキテクチャ概要

| レイヤー | コンポーネント |
|---|---|
| Kubernetes | Kind (ローカル開発用) |
| CNI | Cilium + Hubble UI |
| Service Mesh | Istio (ambient mode) |
| GitOps | ArgoCD + ApplicationSet |
| Ingress | Traefik (CORS / auth / rate-limit middleware) |
| 監視 | Prometheus, Grafana, Loki, Tempo, OTel Collector |
| オブジェクトストレージ | Garage (Loki/Tempo バックエンド) |
| メッセージング | Redpanda (Kafka 互換ブローカー) + Console UI |
| データベース | PostgreSQL |
| マニフェスト生成 | nixidy (Nix + Kustomize) |

## 前提条件

- **Nix** (flakes 有効)
- **direnv** (`devenv` が自動ロードされる)
- **Docker** (Kind が内部で使用)

`direnv allow` すると devenv が起動し、kubectl / kind / helm / cilium-cli / argocd 等が PATH に入る。

## セットアップ

### Dev-fast セットアップ (推奨)

kindnetd (Cilium なし)、シングルノード構成。warm cluster 対応で 2 回目以降は設定が変わっていなければ即完了 (hash gate)。

```bash
bootstrap
```

- `bootstrap --clean` — キャッシュを無視してフルリビルド
- `bootstrap --full` — Cilium モード (`bootstrap-full`) に委譲
- Cold: ~120s / Warm: 即時

> [!NOTE]
> 2回目以降の実行では、クラスタとマニフェストのハッシュを比較して自動的に warm reapply（差分のみ再適用）を行います。フルリビルドが必要な場合は `bootstrap --clean` を使用してください。

### Cilium セットアップ

Cilium + Hubble、worker 1 台。本番に近い CNI 構成でテストしたい場合に使用。

```bash
bootstrap-full
```

- Cold: ~200s

### Full セットアップ

Cilium + Istio (ambient mode) + ArgoCD + worker 2 台のフルスタック構成。

```bash
full-bootstrap
```

> [!NOTE]
> 2回目以降の実行では、クラスタとマニフェストのハッシュを比較して自動的に warm reapply（差分のみ再適用）を行います。フルリビルドが必要な場合は `full-bootstrap --clean` を使用してください。

### ポート一覧

| ポート | サービス | 備考 |
|---|---|---|
| 30081 | Traefik HTTP | |
| 30090 | Prometheus | |
| 30093 | Alertmanager | |
| 30300 | Grafana (admin/admin) | |
| 31235 | Hubble UI | Cilium / Full モードのみ |
| 30082 | Redpanda Console | |
| 30080 | ArgoCD HTTP | Full モードのみ |
| 30443 | ArgoCD HTTPS | Full モードのみ |

### その他のコマンド

```
cluster-up / cluster-down    Kind クラスタの作成・削除
cluster-stop / cluster-start クラスタの停止・再開 (状態保持)
bootstrap-full               Cilium モードセットアップ
benchmark N                  ブートストラップベンチマーク (N回実行)
gen-manifests                nixidy マニフェスト再生成
cilium-install               Cilium + Hubble インストール
istio-install                Istio ambient mode インストール
argocd-bootstrap             ArgoCD ブートストラップ
cloudflared-setup            Cloudflare Tunnel + DNS セットアップ
watch-manifests              nixidy モジュール変更を監視して自動適用
nix-check                    Nix 式の簡易チェック
debug-k8s                    Pod / Event デバッグ
```

## ディレクトリ構成

| ディレクトリ | 説明 |
|---|---|
| `nixidy/` | nixidy モジュール (マニフェスト生成の Nix 定義) |
| `manifests/` | nixidy 生成済みマニフェスト (環境別) |
| `manifests-result/` | レンダリング済みマニフェスト (kubectl apply 対象) |
| `k8s/` | Kind クラスタ設定 (kind-config.yaml, kind-config-lite.yaml, kind-config-dev.yaml) |
| `scripts/` | ブートストラップ・セットアップスクリプト群 |
| `argocd/` | ArgoCD ApplicationSet 定義 |
| `dashboards/` | Grafana ダッシュボード (grafonnet) |
| `otel-collector/` | カスタム OTel Collector ビルド定義 |
| `istio/` | Istio 関連設定 |
| `patches/` | Traefik auth パッチ等 |
| `docs/` | ブートストラップモード・最適化のドキュメント |
| `secrets/` | SOPS 暗号化シークレット |

## アプリケーション開発

アプリケーション (Go / Node.js / React) の開発手順・コマンド・フロントエンド開発については [microservice-app の README](https://github.com/hackz-megalo-cup/microservices-app#readme) を参照。

このリポジトリはインフラ基盤の構築・運用のみを扱う。アプリのデプロイは `microservice-app` 側で `tilt up` または `docker compose up` で行う。

## 関連リポジトリ

- [microservice-app](https://github.com/hackz-megalo-cup/microservice-app) -- アプリケーションコード (Go / Node.js / React)
