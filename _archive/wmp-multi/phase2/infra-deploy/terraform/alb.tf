resource "aws_lb" "internal" {
  count = var.deployment.alb ? 1 : 0

  name               = substr("${local.name_prefix}-alb", 0, 32)
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb[0].id]
  subnets            = [for az in local.two_azs : aws_subnet.alb[az].id]

  enable_deletion_protection = var.environment == "prod"
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.deployment.log_bucket ? [1] : []
    content {
      bucket  = aws_s3_bucket.logs[0].id
      prefix  = "alb"
      enabled = true
    }
  }

  depends_on = [aws_s3_bucket_policy.logs]

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "inbound" {
  count = var.deployment.alb ? 1 : 0

  # Primary target group. With native ECS blue/green, ECS alternates traffic
  # between this target group and aws_lb_target_group.inbound_alternate.
  name        = substr("${local.name_prefix}-inbound", 0, 32)
  port        = var.inbound_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
    path                = var.alb_health_check_path
    protocol            = "HTTP"
  }

  tags = {
    Service = "inbound"
  }
}


resource "aws_lb_target_group" "inbound_alternate" {
  count = var.deployment.alb && var.inbound_blue_green_enabled ? 1 : 0

  name        = trimsuffix(substr("${local.name_prefix}-inbound-alt", 0, 32), "-")
  port        = var.inbound_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
    path                = var.alb_health_check_path
    protocol            = "HTTP"
  }

  tags = {
    Service    = "inbound"
    Deployment = "alternate"
  }
}

resource "aws_lb_listener" "http" {
  count = var.deployment.alb && var.alb_certificate_arn == null ? 1 : 0

  load_balancer_arn = aws_lb.internal[0].arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.inbound[0].arn
  }
}

resource "aws_lb_listener" "https" {
  count = var.deployment.alb && var.alb_certificate_arn != null ? 1 : 0

  load_balancer_arn = aws_lb.internal[0].arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = var.alb_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.inbound[0].arn
  }
}


# Native ECS blue/green requires an ALB listener *rule* ARN, not the listener ARN.
# The rule must reference both target groups and start with exactly one non-zero weight.
# ECS owns the target-group weights during deployments; Terraform therefore ignores
# subsequent action changes made by ECS.
resource "aws_lb_listener_rule" "inbound_blue_green" {
  count = var.deployment.alb && var.inbound_blue_green_enabled ? 1 : 0

  listener_arn = var.alb_certificate_arn == null ? aws_lb_listener.http[0].arn : aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.inbound[0].arn
        weight = 1
      }

      target_group {
        arn    = aws_lb_target_group.inbound_alternate[0].arn
        weight = 0
      }
    }
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }

  lifecycle {
    ignore_changes = [action]
  }
}

resource "aws_lb_target_group" "management" {
  count = var.deployment.alb && var.deployment.management_service ? 1 : 0

  name        = trimsuffix(substr("${local.name_prefix}-mgmt", 0, 32), "-")
  port        = var.management_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
    path                = "/health"
    protocol            = "HTTP"
  }

  tags = { Service = "management" }
}

resource "aws_lb_listener_rule" "management" {
  count = var.deployment.alb && var.deployment.management_service ? 1 : 0

  listener_arn = var.alb_certificate_arn == null ? aws_lb_listener.http[0].arn : aws_lb_listener.https[0].arn
  priority     = 50

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.management[0].arn
  }

  condition {
    path_pattern {
      values = ["/api/v1/management/*", "/management/*"]
    }
  }
}
