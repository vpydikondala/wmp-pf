resource "aws_sqs_queue" "processing_dlq" {
  count = var.deployment.processing_queue ? 1 : 0

  name                      = "${local.name_prefix}-processing-dlq"
  message_retention_seconds = 1209600

  sqs_managed_sse_enabled = !var.deployment.kms
  kms_master_key_id       = var.deployment.kms ? aws_kms_key.application[0].arn : null
}

resource "aws_sqs_queue" "processing" {
  count = var.deployment.processing_queue ? 1 : 0

  name                       = "${local.name_prefix}-processing"
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = 345600

  sqs_managed_sse_enabled = !var.deployment.kms
  kms_master_key_id       = var.deployment.kms ? aws_kms_key.application[0].arn : null

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.processing_dlq[0].arn
    maxReceiveCount     = 5
  })
}

resource "aws_sqs_queue" "datalake_dlq" {
  count = var.deployment.datalake_queue ? 1 : 0

  name                      = "${local.name_prefix}-datalake-dlq"
  message_retention_seconds = 1209600

  sqs_managed_sse_enabled = !var.deployment.kms
  kms_master_key_id       = var.deployment.kms ? aws_kms_key.application[0].arn : null
}

resource "aws_sqs_queue" "datalake" {
  count = var.deployment.datalake_queue ? 1 : 0

  name                       = "${local.name_prefix}-datalake-delivery"
  visibility_timeout_seconds = var.sqs_visibility_timeout_seconds
  message_retention_seconds  = 345600

  sqs_managed_sse_enabled = !var.deployment.kms
  kms_master_key_id       = var.deployment.kms ? aws_kms_key.application[0].arn : null

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.datalake_dlq[0].arn
    maxReceiveCount     = 5
  })
}
