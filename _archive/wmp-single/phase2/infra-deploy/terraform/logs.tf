resource "aws_cloudwatch_log_group" "ecs" {
  for_each = local.enabled_ecs_services

  name              = "/ecs/${local.name_prefix}/${each.key}"
  retention_in_days = var.environment == "prod" ? 90 : 30
  kms_key_id        = var.deployment.kms ? aws_kms_key.application[0].arn : null

  tags = {
    Service = each.key
  }
}
