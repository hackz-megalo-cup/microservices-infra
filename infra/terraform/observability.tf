resource "aws_cloudwatch_log_group" "amp" {
  name              = "/aws/aps/${var.cluster_name}"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_group" "application" {
  for_each = local.app_log_groups

  name              = each.value
  retention_in_days = 30
}

resource "aws_prometheus_workspace" "amp" {
  alias = "${var.cluster_name}-amp"

  logging_configuration {
    log_group_arn = "${aws_cloudwatch_log_group.amp.arn}:*"
  }
}

resource "aws_grafana_workspace" "main" {
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn
  name                     = "${var.cluster_name}-grafana"
  description              = "Managed Grafana workspace for microservices-infra."
  grafana_version          = "10.4"
  data_sources             = ["CLOUDWATCH", "PROMETHEUS", "XRAY"]
}

resource "aws_xray_group" "main" {
  group_name        = "${var.cluster_name}-services"
  filter_expression = "responsetime > 5"

  insights_configuration {
    insights_enabled      = true
    notifications_enabled = false
  }
}

resource "aws_xray_sampling_rule" "baseline" {
  rule_name      = "${var.cluster_name}-baseline"
  priority       = 10
  version        = 1
  reservoir_size = 1
  fixed_rate     = 0.05
  url_path       = "*"
  host           = "*"
  http_method    = "*"
  service_type   = "*"
  service_name   = "*"
  resource_arn   = "*"
}
