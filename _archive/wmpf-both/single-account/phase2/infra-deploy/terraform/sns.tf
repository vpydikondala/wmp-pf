resource "aws_sns_topic" "servicenow" {
  count = var.deployment.sns ? 1 : 0
  name  = "${local.name_prefix}-servicenow-notifications"

  kms_master_key_id = var.deployment.kms ? aws_kms_key.application[0].arn : null
}

resource "aws_sns_topic_subscription" "servicenow_https" {
  for_each = var.deployment.sns ? toset(var.sns_https_endpoints) : toset([])

  topic_arn = aws_sns_topic.servicenow[0].arn
  protocol  = "https"
  endpoint  = each.value
}
