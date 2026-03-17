resource "aws_cloudwatch_log_group" "application" {
  for_each = local.app_log_groups

  name              = each.value
  retention_in_days = 30
}
