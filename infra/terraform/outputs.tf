output "cluster_name" {
  description = "Shared EKS cluster name."
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded certificate data for the EKS cluster."
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA-enabled in-cluster workloads."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "subnet_ids" {
  description = "All cluster subnet IDs."
  value       = local.cluster_subnet_ids
}

output "worker_subnet_ids" {
  description = "Subnet IDs used by the shared managed node group."
  value       = local.worker_subnet_ids
}

output "observability_bucket_name" {
  description = "S3 bucket backing observability migration work."
  value       = aws_s3_bucket.observability.bucket
}

output "amp_workspace_id" {
  description = "Amazon Managed Service for Prometheus workspace ID."
  value       = aws_prometheus_workspace.amp.id
}

output "amp_workspace_endpoint" {
  description = "AMP remote write/query endpoint."
  value       = aws_prometheus_workspace.amp.prometheus_endpoint
}

output "grafana_workspace_id" {
  description = "Amazon Managed Grafana workspace ID."
  value       = aws_grafana_workspace.main.id
}

output "grafana_workspace_endpoint" {
  description = "Amazon Managed Grafana workspace URL."
  value       = aws_grafana_workspace.main.endpoint
}

output "cloudwatch_log_group_names" {
  description = "CloudWatch log groups provisioned for observability migration."
  value = merge(
    { amp = aws_cloudwatch_log_group.amp.name },
    { for key, group in aws_cloudwatch_log_group.application : key => group.name },
  )
}
