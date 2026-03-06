# microservice-infra

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
| データベース | PostgreSQL |
| マニフェスト生成 | nixidy (Nix + Kustomize) |

## 前提条件

- **Nix** (flakes 有効)
- **direnv** (`devenv` が自動ロードされる)
- **Docker** (Kind が内部で使用)

`direnv allow` すると devenv が起動し、kubectl / kind / helm / cilium-cli / argocd 等が PATH に入る。

## セットアップ

### Lite セットアップ (推奨)

Istio・ArgoCD を省略した軽量構成。worker ノード 1 台。アプリのデプロイは `tilt up` で行う。

```bash
bootstrap
```

#### ポート一覧

| ポート | サービス |
|---|---|
| 30081 | Traefik HTTP |
| 30090 | Prometheus |
| 30093 | Alertmanager |
| 30300 | Grafana (admin/admin) |
| 31235 | Hubble UI |

### Full セットアップ

Istio (ambient mode) + ArgoCD + Gateway API を含むフル構成。worker ノード 2 台。

```bash
full-bootstrap
```

#### 追加ポート

| ポート | サービス |
|---|---|
| 30080 | ArgoCD HTTP |
| 30443 | ArgoCD HTTPS |

### その他のコマンド

```
cluster-up / cluster-down    Kind クラスタの作成・削除
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
| `k8s/` | Kind クラスタ設定 (kind-config.yaml, kind-config-lite.yaml) |
| `scripts/` | ブートストラップ・セットアップスクリプト群 |
| `argocd/` | ArgoCD ApplicationSet 定義 |
| `dashboards/` | Grafana ダッシュボード (grafonnet) |
| `otel-collector/` | カスタム OTel Collector ビルド定義 |
| `istio/` | Istio 関連設定 |
| `patches/` | Traefik auth パッチ等 |
| `secrets/` | SOPS 暗号化シークレット |

## アプリケーション開発

アプリケーション (Go / Node.js / React) の開発手順・コマンド・フロントエンド開発については [microservice-app の README](https://github.com/hackz-megalo-cup/microservices-app#readme) を参照。

このリポジトリはインフラ基盤の構築・運用のみを扱う。アプリのデプロイは `microservice-app` 側で `tilt up` または `docker compose up` で行う。

## 関連リポジトリ

- [microservice-app](https://github.com/hackz-megalo-cup/microservice-app) -- アプリケーションコード (Go / Node.js / React)
