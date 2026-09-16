resource "aws_cloudwatch_log_group" "ecs" {
  for_each = local.enabled_ecs_services

  name              = "/ecs/${local.name_prefix}/${each.key}"
  retention_in_days = 365

  kms_key_id = var.deployment.kms ? aws_kms_key.application[0].arn : null

  tags = {
    Service = each.key
  }
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc-flow-logs/${local.name_prefix}"
  retention_in_days = 365

  kms_key_id = var.deployment.kms ? aws_kms_key.application[0].arn : null

  tags = {
    Name    = "${local.name_prefix}-vpc-flow-logs"
    Purpose = "vpc-flow-logs"
  }
}