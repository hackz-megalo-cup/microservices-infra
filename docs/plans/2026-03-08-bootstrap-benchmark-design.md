# Bootstrap Benchmark & Cross-Architecture Design

Date: 2026-03-08

## Goal

1. Bootstrap / full-bootstrap の各ステップ実行時間を計測し、ボトルネックをデータドリブンで特定する
2. 複数回実行して統計値（平均・中央値・最小・最大・標準偏差）を算出する
3. 全 CPU アーキテクチャ（Intel Mac / Apple Silicon / Linux x86_64 / Linux aarch64 / WSL2）に対応する
4. 計測結果に基づき、Phase 2 で最適化を実施する（本ドキュメントは Phase 1 のみ）

## Approach

**Phase 1（本設計）**: 計測フレームワーク + アーキテクチャ検出統一化
**Phase 2（後日）**: 計測結果に基づく最適化（並列化、キャッシュ活用等）

## Architecture

### 新規ファイル

```
scripts/
├── lib/
│   ├── timing.sh      # 計測フレームワーク
│   ├── monitor.sh     # リソースモニター（CPU/メモリ/Docker stats）
│   └── platform.sh    # プラットフォーム検出
├── benchmark.sh       # ベンチマーク実行スクリプト
```

### 変更ファイル

- `scripts/bootstrap.sh` — timed_step で各ステップを包む
- `scripts/full-bootstrap.sh` — 同上
- `devenv.nix` — benchmark コマンド追加
- `.gitignore` — `logs/benchmark/` 追加

---

## 1. 計測フレームワーク (`scripts/lib/timing.sh`)

### API

```bash
source "${SCRIPT_DIR}/lib/timing.sh"

timing_init "bootstrap"                          # セッション開始、環境情報を記録
timed_step "kind-cluster" bash "${SCRIPT_DIR}/cluster-up.sh"   # ステップ計測
timed_step "cilium-install" bash "${SCRIPT_DIR}/cilium-install.sh"
timing_report                                    # サマリー出力 + JSON 保存
```

### 記録項目

| 項目 | 説明 |
|---|---|
| step_name | ステップ識別名 |
| duration_sec | 実行時間（秒、ミリ秒精度） |
| exit_code | 終了ステータス |
| timestamp_start / end | ISO 8601 タイムスタンプ |

### コンソール出力

ステップ完了ごとに1行サマリーを表示し、全ステップ完了後にテーブル形式のレポートを出力する。

---

## 2. リソースモニター (`scripts/lib/monitor.sh`)

各ステップ実行中にバックグラウンドでシステムリソースをサンプリングする。

### 取得メトリクス

| メトリクス | macOS | Linux / WSL2 |
|---|---|---|
| CPU 使用率 | `top -l 1 -s 0` | `/proc/stat` |
| メモリ使用量 | `vm_stat` | `/proc/meminfo` |
| Docker コンテナリソース | `docker stats --no-stream` | 同左 |
| ディスク I/O | `iostat` (利用可能時) | `/proc/diskstats` |
| ネットワーク (参考) | nix build ログからのダウンロード量推定 | 同左 |

### API

```bash
source "${SCRIPT_DIR}/lib/monitor.sh"

start_monitor "$step_name"    # バックグラウンドでサンプリング開始（2秒間隔）
# ... ステップ実行 ...
stop_monitor "$step_name"     # サンプリング停止、結果を集約
```

### 集約値

- CPU: 平均使用率、ピーク使用率
- メモリ: 開始時、終了時、ピーク
- Docker: 実行コンテナ数

---

## 3. プラットフォーム検出 (`scripts/lib/platform.sh`)

全スクリプトで共通のプラットフォーム検出ロジックを提供する。

### 公開変数

| 変数 | 説明 | 例 |
|---|---|---|
| `PLATFORM_OS` | OS 種別 | `darwin` / `linux` |
| `PLATFORM_ARCH` | CPU アーキテクチャ | `aarch64` / `x86_64` |
| `PLATFORM_NIX_SYSTEM` | Nix system string | `aarch64-darwin` / `x86_64-linux` |
| `PLATFORM_LINUX_SYSTEM` | Linux 向け system string | `aarch64-linux` / `x86_64-linux` |
| `PLATFORM_IS_WSL` | WSL2 上かどうか | `true` / `false` |
| `PLATFORM_DOCKER_ARCH` | Docker platform string | `linux/arm64` / `linux/amd64` |

### 対応マトリクス

| 環境 | PLATFORM_OS | PLATFORM_ARCH | PLATFORM_NIX_SYSTEM | PLATFORM_IS_WSL |
|---|---|---|---|---|
| Apple Silicon Mac | darwin | aarch64 | aarch64-darwin | false |
| Intel Mac | darwin | x86_64 | x86_64-darwin | false |
| Linux x86_64 | linux | x86_64 | x86_64-linux | false |
| Linux aarch64 | linux | aarch64 | aarch64-linux | false |
| WSL2 (x86_64) | linux | x86_64 | x86_64-linux | true |

### 現状の問題点と修正内容

1. `load-otel-collector-image.sh`: macOS の `arm64 -> aarch64` マッピングのみ。platform.sh の変数に置き換え
2. `gen-manifests.sh`: `nix eval --raw --impure --expr 'builtins.currentSystem'` を毎回実行。platform.sh の `PLATFORM_NIX_SYSTEM` に置き換え
3. WSL2: Docker 接続チェックを追加

---

## 4. ベンチマークスクリプト (`scripts/benchmark.sh`)

### 使い方

```bash
benchmark.sh [bootstrap|full-bootstrap] [回数(デフォルト3)]
```

### フロー

1. 環境チェック（Docker, Nix, 必要ツール）
2. プラットフォーム情報をログ
3. 指定回数ループ:
   a. `cluster-down.sh` でクリーンアップ
   b. `BENCHMARK_MODE=1` で bootstrap/full-bootstrap を実行
   c. JSON 結果を `logs/benchmark/run_N.json` に保存
4. 全結果を集約して統計レポートを算出
5. コンソールにテーブル出力 + `logs/benchmark/summary_YYYYMMDD_HHMMSS.json` に保存

### 統計レポート出力例

```
============================================================
 Bootstrap Benchmark Summary (3 runs)
 Host: aarch64-darwin / Apple M2 Pro / 32GB
============================================================
 Step                  | Avg    | Median | Min    | Max    | StdDev | CPU Avg | Mem Peak
-----------------------+--------+--------+--------+--------+--------+---------+---------
 kind-cluster          |  45.2s |  44.8s |  42.1s |  48.7s |   2.3s |  65.3%  | 12.4 GB
 cilium-install        |  38.1s |  37.5s |  35.2s |  41.6s |   2.8s |  45.2%  | 13.1 GB
 gen-manifests         |  22.4s |  22.1s |  20.8s |  24.3s |   1.4s |  85.7%  |  9.2 GB
 otel-collector-image  |  95.3s |  94.0s |  88.7s | 103.2s |   6.1s |  72.4%  | 15.8 GB
 garage-deploy         |  35.6s |  35.2s |  33.1s |  38.5s |   2.2s |  30.1%  | 14.2 GB
 observability-stack   |  28.9s |  28.5s |  26.7s |  31.5s |   2.0s |  25.8%  | 15.1 GB
 postgresql            |  18.2s |  17.9s |  16.5s |  20.2s |   1.5s |  20.3%  | 14.8 GB
 traefik               |  12.1s |  11.8s |  10.9s |  13.6s |   1.1s |  18.5%  | 14.5 GB
 wait-pods             |  25.7s |  25.3s |  23.1s |  28.7s |   2.3s |  12.1%  | 14.9 GB
-----------------------+--------+--------+--------+--------+--------+---------+---------
 TOTAL                 | 321.5s | 317.1s | 297.1s | 350.3s |  22.1s |    -    |    -
============================================================
```

### JSON 出力構造

```json
{
  "session": {
    "timestamp": "2026-03-08T12:00:00+09:00",
    "mode": "bootstrap",
    "runs": 3,
    "host": {
      "os": "darwin",
      "arch": "aarch64",
      "nix_system": "aarch64-darwin",
      "cpu_model": "Apple M2 Pro",
      "cpu_cores": 12,
      "memory_gb": 32,
      "docker_version": "27.5.1",
      "is_wsl": false
    }
  },
  "runs": [
    {
      "run_number": 1,
      "steps": [
        {
          "name": "kind-cluster",
          "duration_sec": 45.2,
          "exit_code": 0,
          "resources": {
            "cpu_avg_percent": 65.3,
            "cpu_peak_percent": 95.1,
            "mem_start_mb": 8200,
            "mem_peak_mb": 12400,
            "docker_containers": 3
          }
        }
      ],
      "total_duration_sec": 320.5
    }
  ],
  "statistics": {
    "per_step": {
      "kind-cluster": {
        "avg": 45.2, "median": 44.8, "min": 42.1, "max": 48.7, "stddev": 2.3,
        "cpu_avg": 65.3, "mem_peak_mb": 12400
      }
    },
    "total": {
      "avg": 321.5, "median": 317.1, "min": 297.1, "max": 350.3, "stddev": 22.1
    }
  }
}
```

---

## 5. 既存スクリプトへの変更

### bootstrap.sh / full-bootstrap.sh

各ステップを `timed_step` で包む。通常実行時もステップごとの経過時間が表示されるようになる（軽量なオーバーヘッド）。

変更前:
```bash
echo "=== Step 1: Creating kind cluster ==="
bash "${SCRIPT_DIR}/cluster-up.sh"
```

変更後:
```bash
source "${SCRIPT_DIR}/lib/platform.sh"
source "${SCRIPT_DIR}/lib/timing.sh"
source "${SCRIPT_DIR}/lib/monitor.sh"

timing_init "bootstrap"
timed_step "kind-cluster" bash "${SCRIPT_DIR}/cluster-up.sh"
# ...
timing_report
```

### devenv.nix

```nix
benchmark.exec = ''
  bash "$DEVENV_ROOT/scripts/benchmark.sh" "$@"
'';
```

### .gitignore

```
logs/benchmark/
```

---

## 6. 対応外（Phase 2 で検討）

以下は計測結果を得た後に Phase 2 で検討する:

- ステップの並列実行
- nix build キャッシュの活用最適化
- OTel Collector イメージのプリビルド/キャッシュ
- helm repo update のスキップ（キャッシュ利用）
- kubectl apply の一括化
- kind ノード数の動的調整
