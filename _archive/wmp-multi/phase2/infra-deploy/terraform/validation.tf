resource "terraform_data" "configuration_validation" {
  input = var.environment

  lifecycle {
    precondition {
      condition     = !var.deployment.nat_gateway || var.deployment.nat_az_count >= 1
      error_message = "When nat_gateway=true, nat_az_count must be at least 1."
    }

    precondition {
      condition     = var.deployment.nat_gateway || var.deployment.nat_az_count == 0
      error_message = "When nat_gateway=false, set nat_az_count=0."
    }

    precondition {
      condition     = var.deployment.nat_az_count <= var.deployment.app_az_count
      error_message = "nat_az_count cannot exceed app_az_count."
    }

    precondition {
      condition     = !var.deployment.alb || var.deployment.app_az_count == 2
      error_message = "ALB deployment requires app_az_count=2 because the ALB spans two AZs."
    }

    precondition {
      condition     = !var.deployment.cloudfront || var.deployment.alb
      error_message = "cloudfront=true requires alb=true."
    }

    precondition {
      condition     = !var.deployment.waf || var.deployment.cloudfront
      error_message = "waf=true requires cloudfront=true."
    }

    precondition {
      condition     = !var.deployment.route53 || var.deployment.cloudfront
      error_message = "route53=true requires cloudfront=true."
    }

    precondition {
      condition = (
        length(var.cloudfront_aliases) == 0 ||
        var.cloudfront_acm_certificate_arn != null ||
        (var.deployment.route53 && (var.route53_zone_id != null || var.route53_zone_name != null))
      )
      error_message = "CloudFront aliases require either an existing cloudfront_acm_certificate_arn, or Route53 management with route53_zone_id/route53_zone_name so Terraform can create and DNS-validate the certificate."
    }

    precondition {
      condition     = length(local.enabled_ecs_services) == 0 || (var.deployment.ecs_cluster && var.deployment.ecr)
      error_message = "Any ECS service deployment requires ecs_cluster=true and ecr=true."
    }

    precondition {
      condition     = !var.deployment.inbound_service || var.deployment.alb
      error_message = "inbound_service=true requires alb=true."
    }

    precondition {
      condition = !var.deployment.inbound_service || (
        var.deployment.vpc_endpoints.ecr &&
        var.deployment.vpc_endpoints.s3 &&
        var.deployment.vpc_endpoints.sqs &&
        var.deployment.vpc_endpoints.logs &&
        var.deployment.vpc_endpoints.secrets_manager
      )
      error_message = "inbound_service=true uses an isolated subnet with no NAT route and therefore requires ECR, S3, SQS, CloudWatch Logs, and Secrets Manager VPC endpoints."
    }

    precondition {
      condition = !var.deployment.inbound_service || (
        var.deployment.data_bucket &&
        var.deployment.processing_queue
      )
      error_message = "inbound_service=true requires data_bucket=true and processing_queue=true."
    }

    precondition {
      condition     = !var.deployment.dashboard_sync_service || var.deployment.secrets_manager
      error_message = "dashboard_sync_service=true requires secrets_manager=true for its configured credentials."
    }

    precondition {
      condition = !var.deployment.dashboard_sync_service || (
        var.deployment.vpc_endpoints.ecr &&
        var.deployment.vpc_endpoints.s3 &&
        var.deployment.vpc_endpoints.sqs &&
        var.deployment.vpc_endpoints.logs &&
        var.deployment.vpc_endpoints.secrets_manager
      )
      error_message = "dashboard_sync_service=true is placed on the isolated APP subnet tier and therefore requires ECR, S3, SQS, CloudWatch Logs, and Secrets Manager VPC endpoints."
    }

    precondition {
      condition     = !var.deployment.processor_service || var.deployment.nat_gateway
      error_message = "processor_service=true requires nat_gateway=true in this routed-processor design."
    }

    precondition {
      condition = !var.deployment.processor_service || (
        var.deployment.data_bucket &&
        var.deployment.processing_queue &&
        var.deployment.datalake_queue &&
        var.deployment.rds
      )
      error_message = "processor_service=true requires data_bucket, processing_queue, datalake_queue, and rds."
    }
  }
}


resource "terraform_data" "blue_green_validation" {
  lifecycle {
    precondition {
      condition     = !var.inbound_blue_green_enabled || var.environment == "prod"
      error_message = "inbound_blue_green_enabled is intended for the prod environment in this repository."
    }

    precondition {
      condition     = !var.inbound_blue_green_enabled || (var.deployment.alb && var.deployment.ecs_cluster && var.deployment.inbound_service)
      error_message = "inbound_blue_green_enabled=true requires alb, ecs_cluster, and inbound_service to be enabled."
    }
  }
}
