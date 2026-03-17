data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = var.cluster_name

  common_tags = {
    Project   = "microservices-infra"
    ManagedBy = "terraform"
    Profile   = var.node_desired_size > 2 ? "demo" : "default"
  }

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  vpc_cidr          = "10.42.0.0/16"
  public_subnets    = [for index, _ in local.azs : cidrsubnet(local.vpc_cidr, 8, index)]
  private_subnets   = [for index, _ in local.azs : cidrsubnet(local.vpc_cidr, 8, index + 10)]
  worker_subnet_ids = var.use_nat_gateway ? aws_subnet.private[*].id : aws_subnet.public[*].id
  cluster_subnet_ids = concat(
    aws_subnet.public[*].id,
    aws_subnet.private[*].id,
  )

  app_log_groups = {
    application = "/aws/microservices-infra/application"
    cloudflared = "/aws/microservices-infra/cloudflared"
    otel        = "/aws/microservices-infra/otel-collector"
  }

  observability_bucket_name = var.observability_bucket_name
}
