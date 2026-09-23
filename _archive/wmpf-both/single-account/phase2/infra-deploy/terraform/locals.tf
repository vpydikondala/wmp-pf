data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
  }

  # ----------------------------------------------------------
  # Parent /16 -> first four /21 environment allocations.
  # dev=0, uat=2, prod=3; index 1 (10.0.8.0/21) remains reserved
  # ----------------------------------------------------------
  environment_index = {
    dev  = 0
    uat  = 2
    prod = 3
  }[var.environment]

  environment_cidr = cidrsubnet(var.vpc_cidr, 5, local.environment_index)

  # /21 -> 8 x /24 functional allocation blocks.
  # APP remains the shared private tier for all ALB-facing ECS services.
  # Processor receives the only additional ECS subnet tier because it alone
  # initiates Internet-bound traffic through NAT. Blocks #6 and #7 remain reserved.
  allocation_cidrs = {
    alb       = cidrsubnet(local.environment_cidr, 3, 0)
    app       = cidrsubnet(local.environment_cidr, 3, 1)
    # Historical VPCE allocation retained/reserved. Interface endpoint ENIs are
    # intentionally deployed in APP subnets in the Phase 2 target architecture.
    vpce_reserved = cidrsubnet(local.environment_cidr, 3, 2)
    rds       = cidrsubnet(local.environment_cidr, 3, 3)
    nat       = cidrsubnet(local.environment_cidr, 3, 4)
    processor = cidrsubnet(local.environment_cidr, 3, 5)
    reserved = [
      cidrsubnet(local.environment_cidr, 3, 6),
      cidrsubnet(local.environment_cidr, 3, 7)
    ]
  }

  subnet_cidrs = {
    alb = [
      cidrsubnet(local.allocation_cidrs.alb, 1, 0),
      cidrsubnet(local.allocation_cidrs.alb, 1, 1)
    ]
    app = [
      cidrsubnet(local.allocation_cidrs.app, 1, 0),
      cidrsubnet(local.allocation_cidrs.app, 1, 1)
    ]
    rds = [
      cidrsubnet(local.allocation_cidrs.rds, 1, 0),
      cidrsubnet(local.allocation_cidrs.rds, 1, 1)
    ]
    nat = [
      cidrsubnet(local.allocation_cidrs.nat, 1, 0),
      cidrsubnet(local.allocation_cidrs.nat, 1, 1)
    ]
    processor = [
      cidrsubnet(local.allocation_cidrs.processor, 1, 0),
      cidrsubnet(local.allocation_cidrs.processor, 1, 1)
    ]
  }

  active_azs = slice(var.azs, 0, var.deployment.app_az_count)
  active_az_map = {
    for index, az in local.active_azs : az => index
  }

  two_azs = slice(var.azs, 0, 2)
  two_az_map = {
    for index, az in local.two_azs : az => index
  }

  nat_azs = var.deployment.nat_gateway ? slice(var.azs, 0, var.deployment.nat_az_count) : []
  nat_az_map = {
    for index, az in local.nat_azs : az => index
  }

  interface_endpoints_enabled = anytrue([
    var.deployment.vpc_endpoints.ecr,
    var.deployment.vpc_endpoints.sqs,
    var.deployment.vpc_endpoints.kms,
    var.deployment.vpc_endpoints.logs,
    var.deployment.vpc_endpoints.sts,
    var.deployment.vpc_endpoints.secrets_manager
  ])

  ecs_service_flags = {
    inbound   = var.service_deployment_enabled && var.deployment.inbound_service
    dashboard_sync  = var.service_deployment_enabled && var.deployment.dashboard_sync_service
    processor  = var.service_deployment_enabled && var.deployment.processor_service
    management = var.service_deployment_enabled && var.deployment.management_service
  }

  enabled_ecs_services = {
    for name, enabled in local.ecs_service_flags : name => enabled if enabled
  }

  ecr_repository_names = toset(["inbound", "dashboard_sync", "processor", "management"])

  # For NAT-routed workload AZs without a same-AZ NAT, route to the first
  # enabled NAT. This intentionally permits lower environments to use one NAT
  # for cost while production can remain AZ-local with two NAT gateways.
  workload_nat_target_az = var.deployment.nat_gateway && length(local.nat_azs) > 0 ? {
    for az in local.active_azs : az => (
      contains(local.nat_azs, az) ? az : local.nat_azs[0]
    )
  } : {}

  data_bucket_name = "${substr(replace(lower(local.name_prefix), "_", "-"), 0, 35)}-${data.aws_caller_identity.current.account_id}-data"
  log_bucket_name  = "aws-waf-logs-${substr(replace(lower(local.name_prefix), "_", "-"), 0, 24)}-${data.aws_caller_identity.current.account_id}"

  alb_listener_port = var.alb_certificate_arn != null ? 443 : 80
  alb_origin_policy = var.alb_certificate_arn != null ? "https-only" : "http-only"
}
