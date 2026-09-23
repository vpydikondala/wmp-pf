resource "aws_vpc_endpoint" "s3" {
  count = var.deployment.vpc_endpoints.s3 ? 1 : 0

  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = concat(
    [for rt in aws_route_table.app : rt.id],
    [for rt in aws_route_table.processor : rt.id]
  )

  tags = {
    Name = "${local.name_prefix}-vpce-s3"
  }
}

locals {
  interface_endpoint_services = {
    ecr_api = {
      enabled = var.deployment.vpc_endpoints.ecr
      service = "ecr.api"
    }
    ecr_dkr = {
      enabled = var.deployment.vpc_endpoints.ecr
      service = "ecr.dkr"
    }
    sqs = {
      enabled = var.deployment.vpc_endpoints.sqs
      service = "sqs"
    }
    kms = {
      enabled = var.deployment.vpc_endpoints.kms
      service = "kms"
    }
    logs = {
      enabled = var.deployment.vpc_endpoints.logs
      service = "logs"
    }
    sts = {
      enabled = var.deployment.vpc_endpoints.sts
      service = "sts"
    }
    secretsmanager = {
      enabled = var.deployment.vpc_endpoints.secrets_manager
      service = "secretsmanager"
    }
  }

  enabled_interface_endpoint_services = {
    for name, config in local.interface_endpoint_services : name => config if config.enabled
  }
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.enabled_interface_endpoint_services

  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value.service}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [for az in local.active_azs : aws_subnet.app[az].id]
  security_group_ids  = [aws_security_group.vpce[0].id]
  private_dns_enabled = true

  tags = {
    Name = "${local.name_prefix}-vpce-${replace(each.key, "_", "-")}"
  }
}
