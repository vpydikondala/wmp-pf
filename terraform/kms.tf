data "aws_iam_policy_document" "application_kms" {
  count = var.deployment.kms ? 1 : 0

  #checkov:skip=CKV_AWS_109:KMS key policy grants the account root principal authority to administer this specific key
  #checkov:skip=CKV_AWS_111:KMS key policy Resource "*" refers to the KMS key to which this policy is attached
  #checkov:skip=CKV_AWS_356:KMS key policies use Resource "*" because the policy is scoped by attachment to this specific KMS key
  statement {
    sid    = "EnableAccountPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.aws_region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]

    # KMS key policies use "*" for the key the policy is attached to.
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:*"]
    }
  }
}

resource "aws_kms_key" "application" {
  count = var.deployment.kms ? 1 : 0

  description             = "KMS key for ${local.name_prefix}"
  deletion_window_in_days = var.kms_key_deletion_window
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.application_kms[0].json

  tags = {
    Name = "${local.name_prefix}-kms"
  }
}

resource "aws_kms_alias" "application" {
  count         = var.deployment.kms ? 1 : 0
  name          = "alias/${local.name_prefix}"
  target_key_id = aws_kms_key.application[0].key_id
}