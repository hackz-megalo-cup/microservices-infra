# Terraform AWS Scaffold

`infra/terraform/` は AWS 側リソースを管理する root module です。`default` と `demo` は別 workspace ではなく、同一 state / 同一 EKS クラスタに対する `tfvars` 差分として扱います。

## Managed Scope

- EKS: VPC, subnet, IGW, optional NAT, EKS cluster, managed node group, IAM, EBS CSI add-on
- Observability: AMP workspace, Managed Grafana workspace, CloudWatch log groups, X-Ray baseline resources
- Storage: S3 bucket for observability migration

EKS 内の ArgoCD, cloudflared, Traefik, CloudNativePG, OTel Collector 設定変更は Terraform ではなく nixidy / manifests 側で扱います。

## Usage

```bash
terraform -chdir=infra/terraform init -backend-config=backend.hcl
terraform -chdir=infra/terraform plan -var-file=profiles/default.tfvars
terraform -chdir=infra/terraform plan -var-file=profiles/demo.tfvars
terraform -chdir=infra/terraform apply -var-file=profiles/demo.tfvars
```

ローカル validate のみ行う場合は backend を無効化します。

```bash
terraform -chdir=infra/terraform init -backend=false
terraform -chdir=infra/terraform validate
```

## Profile Model

- `profiles/default.tfvars`: 通常運用。`t3.medium`, 2 nodes, NAT なし, On-Demand
- `profiles/demo.tfvars`: デモ前の一時増強。`t3.large`, 4 nodes, NAT なし, On-Demand

`demo` を適用した後、イベント終了時に `default` を再適用して元のサイズへ戻します。同一 state を共有するため、別クラスタは作成しません。

## Backend

`backend.hcl.example` をコピーして実値を入れ、S3 backend を利用します。コード内に bucket 名や lock table 名は固定していません。

## Notes

- Managed Grafana は `AWS_SSO` を前提に workspace まで作成します。詳細な認証統合や dashboard import は初回スコープ外です。
- Cloudflare DNS / Tunnel は引き続き既存運用を使い、Terraform 管理には含めません。
