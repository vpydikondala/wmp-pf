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
    alb       = { for az, subnet in aws_subnet.alb : az => subnet.cidr_block }
    app       = { for az, subnet in aws_subnet.app : az => subnet.cidr_block }
    vpce      = { for az, subnet in aws_subnet.vpce : az => subnet.cidr_block }
    rds       = { for az, subnet in aws_subnet.rds : az => subnet.cidr_block }
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

output "vpce_subnet_ids" {
  value = { for az, subnet in aws_subnet.vpce : az => subnet.id }
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
