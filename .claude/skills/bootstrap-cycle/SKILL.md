---
name: bootstrap-cycle
description: Run bootstrap test cycles for the Kind cluster. Use when testing bootstrap, setting up the cluster, or debugging cluster creation.
disable-model-invocation: true
---

# Bootstrap Test Cycle

Kindクラスタのブートストラップサイクルを実行し、タイミングとPodの状態を報告する。

## Step 1: テスト対象の選択

ユーザーに以下の選択肢を提示し、選択を待つ：

| Variant | Command | Description | Expected Time |
|---------|---------|-------------|---------------|
| **fast-dev** | `bootstrap` | kindnetd, single node, warm cluster | Cold ~120s, Warm: instant |
| **full** | `full-bootstrap` | Cilium + Istio + ArgoCD + 2 workers | Cold ~200s |
| **lite** | `bootstrap-full` | Cilium + Hubble, 1 worker | Cold ~200s |

追加フラグ：
- `--clean`: 強制コールドスタート（既存クラスタ破棄、ハッシュキャッシュ無視）
- `bootstrap --full`: lite（bootstrap-full）に委譲

## Step 2: ブートストラップ実行

リポジトリルートから選択したコマンドを実行：

- `bootstrap` → `scripts/bootstrap.sh`
- `bootstrap-full` → `scripts/bootstrap-full.sh`
- `full-bootstrap` → `scripts/full-bootstrap.sh`

devenv外の場合は `bash scripts/<script>.sh` で直接実行。

4フェーズ並列実行モデル：
1. **Phase 1**: kind cluster creation + nix manifest generation + image preload（並列）
2. **Phase 2**: Image loading + Cilium/Istio install（lite/fullのみ）
3. **Phase 3**: Service deployment — garage, observability, traefik, redpanda, cloudflared（並列）
4. **Phase 4**: 全Pod readyを待機

## Step 3: 出力の監視

- **"Phase N"**: 現在のフェーズ
- **"WARNING"**: 非致命的な問題
- **"ERROR"**: 致命的な問題（要調査）
- **"Cluster up-to-date"**: ハッシュ一致、ヘルスチェックのみ（warm cluster）
- **"Warm reapply"**: マニフェスト変更のみ再適用

## Step 4: タイミングとPod状態の報告

ブートストラップ完了後、`debug-k8s` を実行して以下を報告：
- 合計ブートストラップ時間（タイミングレポートから）
- フェーズ別内訳
- Pod数: Ready / Total
- Running/Completed以外のPod

## Step 5: 失敗の自動調査

Ready でないPodがある場合、自動で調査する。

### CrashLoopBackOff / Error:
```bash
kubectl logs <pod-name> -n <namespace> --tail=50
kubectl describe pod <pod-name> -n <namespace> | tail -30
```

### Pending:
```bash
kubectl describe pod <pod-name> -n <namespace> | grep -A5 "Events:"
```

### よくある原因と対処:

| Symptom | Cause | Fix |
|---------|-------|-----|
| PostgreSQL Pending | PVC not bound | storage class確認、bootstrap再実行 |
| OTel ImagePullBackOff | カスタムイメージ未ロード | `load-otel-collector-image` |
| Prometheus CRDエラー | CRD未確立 | observabilityステップ再実行 |
| Cilium not ready | kindnetdとのCNI競合 | `--clean`で再スタート |
| Garage setup失敗 | Garage Pod未Ready | 待機後`garage-setup.sh`再試行 |

## ポートアクセス

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

## 注意事項

- **コミット禁止。** このスキルはブートストラップの実行と監視のみ。
- Docker が起動中であること。
- macOS Docker Desktop は最低 8GB RAM 推奨（full variant）。
- warm cluster検出は `.bootstrap-state/`（fast-dev）/ `.bootstrap-state-full/`（full）のハッシュファイルを使用。
