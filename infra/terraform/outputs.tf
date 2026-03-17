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

output "lb_controller_role_arn" {
  description = "IAM role ARN for the AWS Load Balancer Controller (IRSA)."
  value       = aws_iam_role.lb_controller.arn
}

output "vpc_id" {
  description = "VPC ID for the EKS cluster."
  value       = aws_vpc.main.id
}

output "acm_certificate_arn" {
  description = "ACM certificate ARN for app.thirdlf03.com."
  value       = aws_acm_certificate.app.arn
}

output "acm_validation_records" {
  description = "DNS records to add in Cloudflare for ACM certificate validation."
  value = {
    for dvo in aws_acm_certificate.app.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}
