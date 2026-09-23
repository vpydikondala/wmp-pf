# One public route table/NAT/EIP per enabled NAT AZ.
resource "aws_route_table" "nat_public" {
  for_each = local.nat_az_map
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-nat-public-${each.key}"
  }
}

resource "aws_route" "nat_public_internet" {
  for_each = local.nat_az_map

  route_table_id         = aws_route_table.nat_public[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main[0].id
}

resource "aws_route_table_association" "nat_public" {
  for_each = local.nat_az_map

  subnet_id      = aws_subnet.nat_public[each.key].id
  route_table_id = aws_route_table.nat_public[each.key].id
}

resource "aws_eip" "nat" {
  for_each = local.nat_az_map
  domain   = "vpc"

  tags = {
    Name = "${local.name_prefix}-nat-eip-${each.key}"
  }
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_az_map

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.nat_public[each.key].id

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${local.name_prefix}-nat-${each.key}"
  }
}

# One isolated route table per APP application AZ.
# No 0.0.0.0/0 route is created here; AWS service access is through VPC
# endpoints and VPC-local routes only.
resource "aws_route_table" "app" {
  for_each = local.active_az_map
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-app-${each.key}"
  }
}

resource "aws_route_table_association" "app" {
  for_each = local.active_az_map

  subnet_id      = aws_subnet.app[each.key].id
  route_table_id = aws_route_table.app[each.key].id
}

# Dedicated Processor route tables. Processor is the only ECS tier with
# an Internet default route through NAT.
resource "aws_route_table" "processor" {
  for_each = local.active_az_map
  vpc_id   = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-processor-${each.key}"
  }
}

resource "aws_route" "processor_nat" {
  for_each = var.deployment.nat_gateway ? local.active_az_map : {}

  route_table_id         = aws_route_table.processor[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.workload_nat_target_az[each.key]].id
}

resource "aws_route_table_association" "processor" {
  for_each = local.active_az_map

  subnet_id      = aws_subnet.processor[each.key].id
  route_table_id = aws_route_table.processor[each.key].id
}
