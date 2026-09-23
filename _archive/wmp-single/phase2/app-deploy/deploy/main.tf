data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket       = var.infra_state_bucket
    key          = "phase2/infrastructure/${var.environment}/terraform.tfstate"
    region       = var.aws_region
    encrypt      = true
    kms_key_id   = var.infra_state_kms_key_arn
    use_lockfile = true
  }
}

locals {
  i = data.terraform_remote_state.infra.outputs
  services = {
    inbound = { subnet_ids = values(local.i.app_subnet_ids), port = var.inbound_port }
    processor = { subnet_ids = values(local.i.processor_subnet_ids), port = null }
    management = { subnet_ids = values(local.i.app_subnet_ids), port = var.management_port }
  }
}

resource "aws_ecs_task_definition" "service" {
  for_each = local.services
  family = "${var.project_name}-${var.environment}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"
  cpu = tostring(var.ecs_cpu)
  memory = tostring(var.ecs_memory)
  execution_role_arn = local.i.ecs_task_execution_role_arn
  task_role_arn = local.i.ecs_task_role_arns[each.key]

  container_definitions = jsonencode([{
    name = each.key
    image = "${local.i.ecr_repository_urls[each.key]}:${var.container_image_tag}"
    essential = true
    portMappings = each.value.port == null ? [] : [{
      containerPort = each.value.port, hostPort = each.value.port, protocol = "tcp"
    }]
    environment = [
      { name="ENVIRONMENT", value=var.environment },
      { name="AWS_REGION", value=var.aws_region },
      { name="DATA_BUCKET", value=local.i.data_bucket_name },
      { name="PROCESSING_QUEUE_URL", value=local.i.processing_queue_url },
      { name="DATALAKE_QUEUE_URL", value=local.i.datalake_queue_url },
      { name="RDS_ENDPOINT", value=local.i.rds_endpoint },
      { name="RDS_DATABASE", value=local.i.rds_database_name },
      { name="RDS_SECRET_ARN", value=local.i.rds_master_secret_arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group" = "/ecs/${var.project_name}-${var.environment}/${each.key}"
        "awslogs-region" = var.aws_region
        "awslogs-stream-prefix" = each.key
      }
    }
  }])
}

resource "aws_ecs_service" "inbound" {
  name = "${var.project_name}-${var.environment}-inbound"
  cluster = local.i.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.service["inbound"].arn
  desired_count = var.desired_count.inbound
  launch_type = "FARGATE"
  enable_execute_command = true
  network_configuration {
    subnets = values(local.i.app_subnet_ids)
    security_groups = [local.i.ecs_security_group_ids["inbound"]]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = local.i.inbound_primary_target_group_arn
    container_name = "inbound"
    container_port = var.inbound_port

    dynamic "advanced_configuration" {
      for_each = var.environment == "prod" ? [1] : []
      content {
        alternate_target_group_arn = local.i.inbound_alternate_target_group_arn
        production_listener_rule   = local.i.inbound_blue_green_listener_rule_arn
        role_arn                   = local.i.ecs_blue_green_infrastructure_role_arn
      }
    }
  }
  deployment_controller { type = "ECS" }
  deployment_configuration {
    strategy = var.environment == "prod" ? "BLUE_GREEN" : "ROLLING"
    bake_time_in_minutes = var.environment == "prod" ? 10 : null
  }
}

resource "aws_ecs_service" "processor" {
  name = "${var.project_name}-${var.environment}-processor"
  cluster = local.i.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.service["processor"].arn
  desired_count = var.desired_count.processor
  launch_type = "FARGATE"
  enable_execute_command = true
  network_configuration {
    subnets = values(local.i.processor_subnet_ids)
    security_groups = [local.i.ecs_security_group_ids["processor"]]
    assign_public_ip = false
  }
}

resource "aws_ecs_service" "management" {
  name = "${var.project_name}-${var.environment}-management"
  cluster = local.i.ecs_cluster_arn
  task_definition = aws_ecs_task_definition.service["management"].arn
  desired_count = var.desired_count.management
  launch_type = "FARGATE"
  enable_execute_command = true
  network_configuration {
    subnets = values(local.i.app_subnet_ids)
    security_groups = [local.i.ecs_security_group_ids["management"]]
    assign_public_ip = false
  }
  load_balancer {
    target_group_arn = local.i.management_target_group_arn
    container_name = "management"
    container_port = var.management_port
  }
}

resource "aws_ecs_task_definition" "dashboard_sync" {
  family = "${var.project_name}-${var.environment}-dashboard-sync"
  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"
  cpu = tostring(var.ecs_cpu)
  memory = tostring(var.ecs_memory)
  execution_role_arn = local.i.ecs_task_execution_role_arn
  task_role_arn = local.i.ecs_task_role_arns["dashboard_sync"]
  container_definitions = jsonencode([{
    name = "dashboard_sync"
    image = "${local.i.ecr_repository_urls["dashboard_sync"]}:${var.container_image_tag}"
    essential = true
    environment = [
      { name="ENVIRONMENT", value=var.environment },
      { name="AWS_REGION", value=var.aws_region },
      { name="DATA_BUCKET", value=local.i.data_bucket_name },
      { name="PROCESSING_QUEUE_URL", value=local.i.processing_queue_url },
      { name="MERAKI_SECRET_ARN", value=local.i.meraki_secret_arn }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group" = "/ecs/${var.project_name}-${var.environment}/dashboard_sync"
        "awslogs-region" = var.aws_region
        "awslogs-stream-prefix" = "dashboard_sync"
      }
    }
  }])
}

resource "aws_cloudwatch_event_rule" "dashboard_sync" {
  name = "${var.project_name}-${var.environment}-dashboard-sync"
  schedule_expression = var.dashboard_sync_schedule
}
resource "aws_cloudwatch_event_target" "dashboard_sync" {
  rule = aws_cloudwatch_event_rule.dashboard_sync.name
  arn = local.i.ecs_cluster_arn
  role_arn = local.i.dashboard_sync_events_role_arn
  ecs_target {
    task_count = 1
    task_definition_arn = aws_ecs_task_definition.dashboard_sync.arn
    launch_type = "FARGATE"
    network_configuration {
      subnets = values(local.i.processor_subnet_ids)
      security_groups = [local.i.ecs_security_group_ids["dashboard_sync"]]
      assign_public_ip = false
    }
  }
}
