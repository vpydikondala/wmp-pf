resource "aws_ecs_cluster" "main" {
  count = var.deployment.ecs_cluster ? 1 : 0

  name = "${local.name_prefix}-ecs"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "${local.name_prefix}-ecs"
  }
}

resource "aws_ecs_task_definition" "service" {
  for_each = local.enabled_ecs_services

  family                   = "${local.name_prefix}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.ecs_cpu)
  memory                   = tostring(var.ecs_memory)
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[each.key].arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = "${aws_ecr_repository.application[each.key].repository_url}:${var.container_image_tag}"
      essential = true

      portMappings = contains(["inbound", "management"], each.key) ? [
        {
          containerPort = each.key == "inbound" ? var.inbound_port : var.management_port
          hostPort      = each.key == "inbound" ? var.inbound_port : var.management_port
          protocol      = "tcp"
        }
      ] : []

      environment = concat(
        [
          { name = "ENVIRONMENT", value = var.environment },
          { name = "SERVICE_NAME", value = each.key },
          { name = "AWS_REGION", value = var.aws_region },
          { name = "MERAKI_BASE_URL", value = var.meraki_base_url },
          { name = "MERAKI_POLL_PATHS", value = var.meraki_poll_paths },
          { name = "MERAKI_POLL_INTERVAL_SECONDS", value = tostring(var.meraki_poll_interval_seconds) },
          { name = "WEBHOOK_AUTH_REQUIRED", value = tostring(var.webhook_auth_required) },
          { name = "PROCESSOR_POLL_WAIT_SECONDS", value = tostring(var.processor_poll_wait_seconds) }
        ],
        var.deployment.data_bucket ? [
          { name = "DATA_BUCKET", value = aws_s3_bucket.data[0].bucket }
        ] : [],
        var.deployment.processing_queue ? [
          { name = "PROCESSING_QUEUE_URL", value = aws_sqs_queue.processing[0].url }
        ] : [],
        var.deployment.datalake_queue ? [
          { name = "DATALAKE_QUEUE_URL", value = aws_sqs_queue.datalake[0].url }
        ] : [],
        var.deployment.rds ? [
          { name = "RDS_ENDPOINT", value = aws_db_instance.platform[0].address },
          { name = "RDS_PORT", value = tostring(aws_db_instance.platform[0].port) },
          { name = "RDS_DATABASE", value = var.rds_database_name },
          { name = "RDS_SECRET_ARN", value = aws_db_instance.platform[0].master_user_secret[0].secret_arn }
        ] : [],
        var.deployment.sns ? [
          { name = "SERVICENOW_SNS_TOPIC_ARN", value = aws_sns_topic.servicenow[0].arn }
        ] : [],
        var.deployment.secrets_manager ? [
          { name = "MERAKI_SECRET_ARN", value = aws_secretsmanager_secret.meraki[0].arn }
        ] : []
      )

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs[each.key].name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = each.key
        }
      }
    }
  ])

  tags = {
    Service = each.key
  }
}

resource "aws_ecs_service" "inbound" {
  count = var.deployment.inbound_service ? 1 : 0

  name            = "${local.name_prefix}-inbound"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.service["inbound"].arn
  desired_count   = var.ecs_desired_count.inbound
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_execute_command             = true
  wait_for_steady_state              = true

  deployment_controller {
    type = "ECS"
  }

  deployment_configuration {
    strategy             = var.inbound_blue_green_enabled ? "BLUE_GREEN" : "ROLLING"
    bake_time_in_minutes = var.inbound_blue_green_enabled ? var.inbound_blue_green_bake_time_minutes : null
  }

  # The ECS deployment circuit breaker is for ROLLING deployments. Native
  # BLUE_GREEN uses its own deployment stages/health checks and may optionally
  # add CloudWatch deployment alarms or lifecycle hooks for richer rollback gates.
  dynamic "deployment_circuit_breaker" {
    for_each = var.inbound_blue_green_enabled ? [] : [1]
    content {
      enable   = true
      rollback = true
    }
  }

  network_configuration {
    subnets          = [for az in local.active_azs : aws_subnet.app[az].id]
    security_groups  = [aws_security_group.ecs["inbound"].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.inbound[0].arn
    container_name   = "inbound"
    container_port   = var.inbound_port

    dynamic "advanced_configuration" {
      for_each = var.inbound_blue_green_enabled ? [1] : []
      content {
        alternate_target_group_arn = aws_lb_target_group.inbound_alternate[0].arn
        production_listener_rule   = aws_lb_listener_rule.inbound_blue_green[0].arn
        role_arn                   = aws_iam_role.ecs_blue_green_infrastructure[0].arn
      }
    }
  }

  depends_on = [
    aws_lb_listener.http,
    aws_lb_listener.https,
    aws_lb_listener_rule.inbound_blue_green,
    aws_iam_role_policy_attachment.ecs_blue_green_infrastructure
  ]

  timeouts {
    create = "60m"
    update = "60m"
  }
}

resource "aws_ecs_service" "outbound" {
  count = var.deployment.outbound_service ? 1 : 0

  name            = "${local.name_prefix}-outbound"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.service["outbound"].arn
  desired_count   = var.ecs_desired_count.outbound
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  enable_execute_command             = true

  network_configuration {
    subnets          = [for az in local.active_azs : aws_subnet.app[az].id]
    security_groups  = [aws_security_group.ecs["outbound"].id]
    assign_public_ip = false
  }
}

resource "aws_ecs_service" "processor" {
  count = var.deployment.processor_service ? 1 : 0

  name            = "${local.name_prefix}-processor"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.service["processor"].arn
  desired_count   = var.ecs_desired_count.processor
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200
  enable_execute_command             = true

  network_configuration {
    subnets          = [for az in local.active_azs : aws_subnet.processor[az].id]
    security_groups  = [aws_security_group.ecs["processor"].id]
    assign_public_ip = false
  }
}

resource "aws_ecs_service" "management" {
  count = var.deployment.management_service ? 1 : 0

  name            = "${local.name_prefix}-management"
  cluster         = aws_ecs_cluster.main[0].id
  task_definition = aws_ecs_task_definition.service["management"].arn
  desired_count   = var.ecs_desired_count.management
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_execute_command             = true
  wait_for_steady_state              = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = [for az in local.active_azs : aws_subnet.app[az].id]
    security_groups  = [aws_security_group.ecs["management"].id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.management[0].arn
    container_name   = "management"
    container_port   = var.management_port
  }

  depends_on = [aws_lb_listener_rule.management]
}
