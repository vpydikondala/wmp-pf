output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "parent_network_cidr" {
  description = "Parent /16 network allocation supplied to Terraform."
  value       = var.vpc_cidr
}

output "vpc_cidr" {
  description = "Actual environment VPC CIDR derived from the parent /16."
  value       = local.environment_cidr
}

output "environment_cidr" {
  description = "Terraform-derived /21 for this environment."
  value       = local.environment_cidr
}

output "allocation_cidrs" {
  description = "The /24 functional allocation blocks inside the environment /21."
  value       = local.allocation_cidrs
}


output "subnet_cidrs" {
  description = "Actual /25 subnet CIDRs per functional tier and AZ index."
  value       = local.subnet_cidrs
}

output "deployed_subnet_cidrs" {
  description = "Actual subnet CIDRs deployed in this environment, keyed by tier and AZ."
  value = {
    alb  = { for az, subnet in aws_subnet.alb : az => subnet.cidr_block }
    app  = { for az, subnet in aws_subnet.app : az => subnet.cidr_block }
    rds  = { for az, subnet in aws_subnet.rds : az => subnet.cidr_block }
    nat       = { for az, subnet in aws_subnet.nat_public : az => subnet.cidr_block }
    processor = { for az, subnet in aws_subnet.processor : az => subnet.cidr_block }
  }
}

# APP subnet tier is shared by all ALB-facing ECS services and has no NAT default route.
output "app_subnet_ids" {
  value = { for az, subnet in aws_subnet.app : az => subnet.id }
}

output "inbound_subnet_ids" {
  description = "ALB-facing ECS subnet IDs. These are the APP subnets and have no NAT default route."
  value       = { for az, subnet in aws_subnet.app : az => subnet.id }
}

output "processor_subnet_ids" {
  value = { for az, subnet in aws_subnet.processor : az => subnet.id }
}


output "alb_subnet_ids" {
  value = { for az, subnet in aws_subnet.alb : az => subnet.id }
}


output "rds_subnet_ids" {
  value = { for az, subnet in aws_subnet.rds : az => subnet.id }
}

output "nat_gateway_ids" {
  value = { for az, nat in aws_nat_gateway.this : az => nat.id }
}

output "nat_eip_public_ips" {
  value = { for az, eip in aws_eip.nat : az => eip.public_ip }
}

output "internal_alb_dns_name" {
  value = try(aws_lb.internal[0].dns_name, null)
}

output "cloudfront_domain_name" {
  value = try(aws_cloudfront_distribution.api[0].domain_name, null)
}

output "data_bucket_name" {
  value = try(aws_s3_bucket.data[0].bucket, null)
}

output "log_bucket_name" {
  value = try(aws_s3_bucket.logs[0].bucket, null)
}

output "processing_queue_url" {
  value = try(aws_sqs_queue.processing[0].url, null)
}

output "datalake_queue_url" {
  value = try(aws_sqs_queue.datalake[0].url, null)
}

output "servicenow_sns_topic_arn" {
  value = try(aws_sns_topic.servicenow[0].arn, null)
}

output "ecr_repository_urls" {
  value = { for name, repository in aws_ecr_repository.application : name => repository.repository_url }
}

output "rds_endpoint" {
  value = try(aws_db_instance.platform[0].address, null)
}

output "rds_master_secret_arn" {
  description = "Secrets Manager ARN managed by RDS."
  value       = try(aws_db_instance.platform[0].master_user_secret[0].secret_arn, null)
  sensitive   = true
}

output "route53_hosted_zone_id" {
  description = "Effective Route53 hosted zone ID when Route53 is enabled."
  value       = local.route53_effective_zone_id
}

output "route53_created_name_servers" {
  description = "Name servers when Terraform created the public hosted zone. Delegate the registered domain/subdomain to these servers."
  value       = try(aws_route53_zone.public[0].name_servers, [])
}

output "cloudfront_certificate_arn" {
  description = "Effective CloudFront ACM certificate ARN, whether supplied or created by Terraform."
  value       = local.cloudfront_certificate_arn
}


output "inbound_deployment_strategy" {
  description = "Deployment strategy used by the ALB-facing inbound ECS service."
  value       = var.inbound_blue_green_enabled ? "BLUE_GREEN" : "ROLLING"
}

output "inbound_primary_target_group_arn" {
  description = "Primary inbound ALB target group ARN."
  value       = var.deployment.alb ? aws_lb_target_group.inbound[0].arn : null
}

output "inbound_alternate_target_group_arn" {
  description = "Alternate inbound ALB target group ARN used for native ECS blue/green."
  value       = var.deployment.alb && var.inbound_blue_green_enabled ? aws_lb_target_group.inbound_alternate[0].arn : null
}


output "ecs_cluster_name" {
  description = "ECS cluster consumed by the application deployment repository."
  value       = try(aws_ecs_cluster.main[0].name, null)
}

output "ecs_cluster_arn" {
  description = "ECS cluster ARN consumed by the application deployment repository."
  value       = try(aws_ecs_cluster.main[0].arn, null)
}

output "ecs_task_execution_role_arn" {
  description = "Shared ECS execution role ARN."
  value       = try(aws_iam_role.ecs_execution[0].arn, null)
}

output "ecs_task_role_arns" {
  description = "Per-service ECS task role ARNs."
  value       = { for name, role in aws_iam_role.ecs_task : name => role.arn }
}

output "ecs_security_group_ids" {
  description = "Per-service ECS security group IDs."
  value       = { for name, sg in aws_security_group.ecs : name => sg.id }
}

output "management_target_group_arn" {
  value = try(aws_lb_target_group.management[0].arn, null)
}

output "application_contract" {
  description = "Non-secret infrastructure contract consumed by the application repository."
  value = {
    cluster_name              = try(aws_ecs_cluster.main[0].name, null)
    app_subnet_ids            = [for az in local.active_azs : aws_subnet.app[az].id]
    processor_subnet_ids      = [for az in local.active_azs : aws_subnet.processor[az].id]
    processing_queue_url      = try(aws_sqs_queue.processing[0].url, null)
    datalake_queue_url        = try(aws_sqs_queue.datalake[0].url, null)
    data_bucket_name          = try(aws_s3_bucket.data[0].bucket, null)
    rds_endpoint              = try(aws_db_instance.platform[0].address, null)
    rds_database              = var.rds_database_name
    management_target_group   = try(aws_lb_target_group.management[0].arn, null)
    inbound_target_group      = try(aws_lb_target_group.inbound[0].arn, null)
    inbound_alt_target_group  = try(aws_lb_target_group.inbound_alternate[0].arn, null)
    ecr_repository_urls       = { for name, repository in aws_ecr_repository.application : name => repository.repository_url }
  }
}

output "dashboard_sync_events_role_arn" {
  value = aws_iam_role.dashboard_sync_events.arn
}

output "rds_database_name" {
  value = var.rds_database_name
}

output "meraki_secret_arn" {
  value     = try(aws_secretsmanager_secret.meraki[0].arn, null)
  sensitive = true
}

output "inbound_blue_green_listener_rule_arn" {
  value = try(aws_lb_listener_rule.inbound_blue_green[0].arn, null)
}

output "ecs_blue_green_infrastructure_role_arn" {
  value = try(aws_iam_role.ecs_blue_green_infrastructure[0].arn, null)
}
