resource "aws_s3_bucket" "data" {
  count         = var.deployment.data_bucket ? 1 : 0
  bucket        = local.data_bucket_name
  force_destroy = var.data_bucket_force_destroy

  # Event notifications are not required for this application data bucket.
  # Cross-region replication is outside the scope of this functional test environment.
  #checkov:skip=CKV2_AWS_62:Application data bucket does not require S3 event-driven processing
  #checkov:skip=CKV_AWS_144:Functional test environment does not require cross-region disaster recovery

  tags = {
    Name = local.data_bucket_name
    Type = "application-data"
  }
}

resource "aws_s3_bucket_public_access_block" "data" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "data" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "data" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.deployment.kms ? "aws:kms" : "AES256"
      kms_master_key_id = var.deployment.kms ? aws_kms_key.application[0].arn : null
    }

    bucket_key_enabled = var.deployment.kms
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  rule {
    id     = "data-noncurrent-version-retention"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = var.s3_data_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.data]
}

resource "aws_s3_bucket_policy" "data_tls" {
  count  = var.deployment.data_bucket ? 1 : 0
  bucket = aws_s3_bucket.data[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.data[0].arn,
          "${aws_s3_bucket.data[0].arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}


# -----------------------------------------------------------------------------
# Central log archive bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "logs" {
  count         = var.deployment.log_bucket ? 1 : 0
  bucket        = local.log_bucket_name
  force_destroy = var.log_bucket_force_destroy

  # The central log archive is a destination, not an event-processing bucket.
  # Cross-region replication is outside the scope of this functional test environment.
  #checkov:skip=CKV2_AWS_62:Central log archive does not require S3 event-driven processing
  #checkov:skip=CKV_AWS_144:Functional test environment does not require cross-region disaster recovery
  #checkov:skip=CKV_AWS_145:Log delivery bucket uses S3 managed encryption for compatibility with AWS log delivery services

  tags = {
    Name = local.log_bucket_name
    Type = "central-log-archive"
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count  = var.deployment.log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "logs" {
  count  = var.deployment.log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count  = var.deployment.log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  count  = var.deployment.log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id

  rule {
    id     = "log-retention"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }

  depends_on = [aws_s3_bucket_versioning.logs]
}

data "aws_iam_policy_document" "log_bucket" {
  count = var.deployment.log_bucket ? 1 : 0

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.logs[0].arn,
      "${aws_s3_bucket.logs[0].arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.alb ? [1] : []

    content {
      sid    = "AllowALBLogDelivery"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["logdelivery.elasticloadbalancing.amazonaws.com"]
      }

      actions = ["s3:PutObject"]

      resources = [
        "${aws_s3_bucket.logs[0].arn}/alb/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      ]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.waf ? [1] : []

    content {
      sid    = "AWSWAFLogDeliveryAclCheck"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }

      actions = [
        "s3:GetBucketAcl",
        "s3:ListBucket"
      ]

      resources = [
        aws_s3_bucket.logs[0].arn
      ]

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:${data.aws_partition.current.partition}:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"]
      }
    }
  }

  dynamic "statement" {
    for_each = var.deployment.waf ? [1] : []

    content {
      sid    = "AWSWAFLogDeliveryWrite"
      effect = "Allow"

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }

      actions = ["s3:PutObject"]

      resources = [
        "${aws_s3_bucket.logs[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
      ]

      condition {
        test     = "StringEquals"
        variable = "s3:x-amz-acl"
        values   = ["bucket-owner-full-control"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = ["arn:${data.aws_partition.current.partition}:logs:us-east-1:${data.aws_caller_identity.current.account_id}:*"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  count  = var.deployment.log_bucket ? 1 : 0
  bucket = aws_s3_bucket.logs[0].id
  policy = data.aws_iam_policy_document.log_bucket[0].json
}