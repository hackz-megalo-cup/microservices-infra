variable "aws_region" {
  description = "AWS region for all managed resources."
  type        = string
  default     = "ap-northeast-1"
}

variable "cluster_name" {
  description = "Name of the shared EKS cluster that default/demo profiles mutate."
  type        = string
  default     = "microservices-infra-eks"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.32"
}

variable "use_nat_gateway" {
  description = "Whether worker nodes should use private subnets with a NAT gateway."
  type        = bool
  default     = false
}

variable "use_spot" {
  description = "Whether the managed node group should use Spot instances."
  type        = bool
  default     = false
}

variable "node_instance_type" {
  description = "EC2 instance type for the shared managed node group."
  type        = string
  default     = "t3.large"
}

variable "node_disk_size" {
  description = "Root volume size in GiB for the shared managed node group."
  type        = number
  default     = 80
}

variable "node_desired_size" {
  description = "Desired node count for the shared managed node group."
  type        = number
  default     = 5
}

variable "node_min_size" {
  description = "Minimum node count for the shared managed node group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum node count for the shared managed node group."
  type        = number
  default     = 6
}

variable "observability_bucket_name" {
  description = "S3 bucket name for Loki/Tempo object storage."
  type        = string
  default     = "microservices-infra-eks-obs"
}

variable "cloudflare_tunnel_id" {
  description = "Cloudflare Tunnel ID for cloudflared ingress."
  type        = string
  default     = "8fc158d4-7a76-4472-bddd-f58f461c880e"
}
