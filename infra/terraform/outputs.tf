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

output "cloudwatch_log_group_names" {
  description = "CloudWatch log groups for application observability."
  value       = { for key, group in aws_cloudwatch_log_group.application : key => group.name }
}
