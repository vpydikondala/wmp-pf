resource "aws_vpc" "main" {
  cidr_block           = local.environment_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  # CloudFront VPC Origins require an IGW attached to the VPC even though
  # origin traffic itself does not route through the IGW.
  count  = (var.deployment.nat_gateway || var.deployment.cloudfront) ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# APP ECS subnets follow app_az_count and have no Internet/NAT default route.
# All ALB-facing ECS services use this tier.
resource "aws_subnet" "app" {
  for_each = local.active_az_map

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.app[each.value]

  tags = {
    Name = "${local.name_prefix}-app-${each.key}"
    Tier = "application"
  }
}

# Processor ECS subnets are isolated from Inbound and use their own route tables.
# Per the requested design these subnets receive NAT default routes.
resource "aws_subnet" "processor" {
  for_each = local.active_az_map

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.processor[each.value]

  tags = {
    Name = "${local.name_prefix}-processor-${each.key}"
    Tier = "processor-application"
  }
}

# ALB subnets exist only when ALB is enabled and always span two AZs.
resource "aws_subnet" "alb" {
  for_each = var.deployment.alb ? local.two_az_map : {}

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.alb[each.value]

  tags = {
    Name = "${local.name_prefix}-alb-${each.key}"
    Tier = "alb"
  }
}

# Interface-endpoint subnets only exist when at least one interface endpoint is enabled.
resource "aws_subnet" "vpce" {
  for_each = local.interface_endpoints_enabled ? local.active_az_map : {}

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.vpce[each.value]

  tags = {
    Name = "${local.name_prefix}-vpce-${each.key}"
    Tier = "vpce"
  }
}

# RDS subnet group must cover at least two AZs, even for a Single-AZ DB instance.
resource "aws_subnet" "rds" {
  for_each = var.deployment.rds ? local.two_az_map : {}

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = local.subnet_cidrs.rds[each.value]

  tags = {
    Name = "${local.name_prefix}-rds-${each.key}"
    Tier = "database"
  }
}

resource "aws_subnet" "nat_public" {
  for_each = local.nat_az_map

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = local.subnet_cidrs.nat[each.value]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-nat-public-${each.key}"
    Tier = "public-egress"
  }
}

# Isolated ALB route table.
resource "aws_route_table" "alb" {
  count  = var.deployment.alb ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-alb"
  }
}

resource "aws_route_table_association" "alb" {
  for_each       = aws_subnet.alb
  subnet_id      = each.value.id
  route_table_id = aws_route_table.alb[0].id
}

# Isolated interface endpoint route table.
resource "aws_route_table" "vpce" {
  count  = local.interface_endpoints_enabled ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-vpce"
  }
}

resource "aws_route_table_association" "vpce" {
  for_each       = aws_subnet.vpce
  subnet_id      = each.value.id
  route_table_id = aws_route_table.vpce[0].id
}

# Isolated RDS route table.
resource "aws_route_table" "rds" {
  count  = var.deployment.rds ? 1 : 0
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-rds"
  }
}

resource "aws_route_table_association" "rds" {
  for_each       = aws_subnet.rds
  subnet_id      = each.value.id
  route_table_id = aws_route_table.rds[0].id
}
