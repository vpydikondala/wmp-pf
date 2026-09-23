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

# Application task definitions and ECS services are intentionally NOT created here.
# They are owned by the separate application repository after infrastructure exists.
