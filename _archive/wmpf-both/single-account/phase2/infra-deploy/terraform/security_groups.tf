data "aws_ec2_managed_prefix_list" "cloudfront_origin_facing" {
  count = var.deployment.cloudfront ? 1 : 0
  name  = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  count       = var.deployment.alb ? 1 : 0
  name        = "${local.name_prefix}-sg-alb"
  description = "Internal ALB security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-sg-alb"
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_cloudfront" {
  count = var.deployment.alb && var.deployment.cloudfront ? 1 : 0

  security_group_id = aws_security_group.alb[0].id
  prefix_list_id     = data.aws_ec2_managed_prefix_list.cloudfront_origin_facing[0].id
  from_port          = local.alb_listener_port
  to_port            = local.alb_listener_port
  ip_protocol        = "tcp"
  description        = "CloudFront VPC origin traffic"
}

resource "aws_vpc_security_group_ingress_rule" "alb_test_cidrs" {
  for_each = var.deployment.alb ? toset(var.alb_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.alb[0].id
  cidr_ipv4         = each.value
  from_port          = local.alb_listener_port
  to_port            = local.alb_listener_port
  ip_protocol        = "tcp"
  description        = "Explicit direct ALB test ingress"
}

resource "aws_security_group" "ecs" {
  for_each = local.enabled_ecs_services

  name        = "${local.name_prefix}-sg-${each.key}"
  description = "${each.key} ECS service"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name    = "${local.name_prefix}-sg-${each.key}"
    Service = each.key
  }
}

resource "aws_vpc_security_group_ingress_rule" "inbound_from_alb" {
  count = var.deployment.inbound_service ? 1 : 0

  security_group_id            = aws_security_group.ecs["inbound"].id
  referenced_security_group_id = aws_security_group.alb[0].id
  from_port                    = var.inbound_port
  to_port                      = var.inbound_port
  ip_protocol                  = "tcp"
  description                  = "Inbound API traffic from internal ALB"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_inbound" {
  count = var.deployment.inbound_service ? 1 : 0

  security_group_id            = aws_security_group.alb[0].id
  referenced_security_group_id = aws_security_group.ecs["inbound"].id
  from_port                    = var.inbound_port
  to_port                      = var.inbound_port
  ip_protocol                  = "tcp"
  description                  = "ALB to inbound ECS"
}

# ECS tasks need HTTPS for AWS APIs/endpoints; dashboard_sync also uses HTTPS to Meraki.
resource "aws_vpc_security_group_egress_rule" "ecs_https" {
  for_each = local.enabled_ecs_services

  security_group_id = aws_security_group.ecs[each.key].id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS egress for AWS APIs/endpoints and approved external APIs"
}

resource "aws_security_group" "rds" {
  count       = var.deployment.rds ? 1 : 0
  name        = "${local.name_prefix}-sg-rds"
  description = "PostgreSQL RDS security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-sg-rds"
  }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_processor" {
  count = var.deployment.rds && var.deployment.processor_service ? 1 : 0

  security_group_id            = aws_security_group.rds[0].id
  referenced_security_group_id = aws_security_group.ecs["processor"].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from processor ECS"
}

resource "aws_vpc_security_group_egress_rule" "processor_to_rds" {
  count = var.deployment.rds && var.deployment.processor_service ? 1 : 0

  security_group_id            = aws_security_group.ecs["processor"].id
  referenced_security_group_id = aws_security_group.rds[0].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Processor to PostgreSQL"
}

resource "aws_security_group" "vpce" {
  count       = local.interface_endpoints_enabled ? 1 : 0
  name        = "${local.name_prefix}-sg-vpce"
  description = "Interface VPC endpoint security group"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-sg-vpce"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_from_ecs" {
  for_each = local.interface_endpoints_enabled ? local.enabled_ecs_services : {}

  security_group_id            = aws_security_group.vpce[0].id
  referenced_security_group_id = aws_security_group.ecs[each.key].id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "HTTPS from ${each.key} ECS to interface endpoints"
}

resource "aws_vpc_security_group_ingress_rule" "management_from_alb" {
  count = var.deployment.management_service ? 1 : 0

  security_group_id            = aws_security_group.ecs["management"].id
  referenced_security_group_id = aws_security_group.alb[0].id
  from_port                    = var.management_port
  to_port                      = var.management_port
  ip_protocol                  = "tcp"
  description                  = "Management UI/API traffic from internal ALB"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_management" {
  count = var.deployment.management_service ? 1 : 0

  security_group_id            = aws_security_group.alb[0].id
  referenced_security_group_id = aws_security_group.ecs["management"].id
  from_port                    = var.management_port
  to_port                      = var.management_port
  ip_protocol                  = "tcp"
  description                  = "ALB to management ECS"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_management" {
  count = var.deployment.rds && var.deployment.management_service ? 1 : 0

  security_group_id            = aws_security_group.rds[0].id
  referenced_security_group_id = aws_security_group.ecs["management"].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from management ECS"
}

resource "aws_vpc_security_group_egress_rule" "management_to_rds" {
  count = var.deployment.rds && var.deployment.management_service ? 1 : 0

  security_group_id            = aws_security_group.ecs["management"].id
  referenced_security_group_id = aws_security_group.rds[0].id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Management ECS to PostgreSQL"
}
