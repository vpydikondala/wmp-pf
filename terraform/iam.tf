data "aws_iam_policy_document" "ecs_task_execution_assume" {
  count = var.deployment.ecs_cluster ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  count = var.deployment.ecs_cluster ? 1 : 0

  name               = "${local.name_prefix}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume[0].json
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  count = var.deployment.ecs_cluster ? 1 : 0

  role       = aws_iam_role.ecs_execution[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_task_assume" {
  for_each = local.enabled_ecs_services

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task" {
  for_each = local.enabled_ecs_services

  name               = "${local.name_prefix}-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume[each.key].json

  tags = {
    Service = each.key
  }
}

data "aws_iam_policy_document" "ecs_task" {
  for_each = local.enabled_ecs_services

  dynamic "statement" {
    for_each = var.deployment.data_bucket && contains(["inbound", "outbound", "processor"], each.key) ? [1] : []
    content {
      sid = "DataBucket"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket"
      ]
      resources = [
        aws_s3_bucket.data[0].arn,
        "${aws_s3_bucket.data[0].arn}/*"
      ]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.processing_queue && contains(["inbound", "outbound", "processor"], each.key) ? [1] : []
    content {
      sid = "ProcessingQueue"
      actions = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ]
      resources = [aws_sqs_queue.processing[0].arn]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.datalake_queue && each.key == "processor" ? [1] : []
    content {
      sid = "DataLakeQueue"
      actions = [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:GetQueueUrl"
      ]
      resources = [aws_sqs_queue.datalake[0].arn]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.sns ? [1] : []
    content {
      sid       = "ServiceNowNotifications"
      actions   = ["sns:Publish"]
      resources = [aws_sns_topic.servicenow[0].arn]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.rds && contains(["processor", "management"], each.key) ? [1] : []
    content {
      sid       = "RDSMasterSecret"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [aws_db_instance.platform[0].master_user_secret[0].secret_arn]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.secrets_manager && contains(["inbound", "outbound"], each.key) ? [1] : []
    content {
      sid       = "MerakiSecret"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = [aws_secretsmanager_secret.meraki[0].arn]
    }
  }

  dynamic "statement" {
    for_each = var.deployment.kms ? [1] : []
    content {
      sid = "ApplicationKMS"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey"
      ]
      resources = [aws_kms_key.application[0].arn]
    }
  }
}

resource "aws_iam_role_policy" "ecs_task" {
  for_each = local.enabled_ecs_services

  name   = "${local.name_prefix}-${each.key}-task-policy"
  role   = aws_iam_role.ecs_task[each.key].id
  policy = data.aws_iam_policy_document.ecs_task[each.key].json
}


# Amazon ECS native blue/green needs an infrastructure role that ECS itself can
# assume to update ALB listener rules and target-group registrations.
data "aws_iam_policy_document" "ecs_blue_green_infrastructure_assume" {
  count = var.deployment.ecs_cluster && var.inbound_blue_green_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_blue_green_infrastructure" {
  count = var.deployment.ecs_cluster && var.inbound_blue_green_enabled ? 1 : 0

  name               = "${local.name_prefix}-ecs-blue-green-lb"
  assume_role_policy = data.aws_iam_policy_document.ecs_blue_green_infrastructure_assume[0].json

  tags = {
    Purpose = "ecs-native-blue-green-load-balancer-management"
  }
}

resource "aws_iam_role_policy_attachment" "ecs_blue_green_infrastructure" {
  count = var.deployment.ecs_cluster && var.inbound_blue_green_enabled ? 1 : 0

  role       = aws_iam_role.ecs_blue_green_infrastructure[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}
