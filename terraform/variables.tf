# ============================================================
# GENERAL
# ============================================================

variable "aws_region" {
  description = "AWS region for regional resources."
  type        = string
  default     = "eu-west-2"
}

variable "environment" {
  description = "Deployment environment."
  type        = string

  validation {
    condition     = contains(["dev", "uat", "prod"], var.environment)
    error_message = "environment must be one of: dev, uat, prod."
  }
}

variable "project_name" {
  description = "Project/application name."
  type        = string
}

variable "owner" {
  description = "Infrastructure owner/team."
  type        = string
}

# ============================================================
# NETWORK
# ============================================================

variable "vpc_cidr" {
  description = "Parent /16 CIDR supplied to every environment. Terraform derives the environment /21 from environment."
  type        = string

  validation {
    condition     = can(cidrsubnet(var.vpc_cidr, 5, 0)) && tonumber(split("/", var.vpc_cidr)[1]) == 16
    error_message = "vpc_cidr must be a valid /16 CIDR."
  }
}

variable "azs" {
  description = "Ordered AZ list. Supply at least two AZs because ALB/RDS may require two even when app_az_count is 1."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2
    error_message = "Provide at least two Availability Zones."
  }
}

# ============================================================
# DEPLOYMENT FLAGS
# ============================================================

variable "deployment" {
  description = "Environment deployment profile. Individual resources can be enabled/disabled."

  type = object({
    app_az_count = number

    nat_gateway  = bool
    nat_az_count = number

    alb        = bool
    cloudfront = bool
    waf        = bool
    route53    = bool

    ecr             = bool
    kms             = bool
    secrets_manager = bool

    data_bucket = bool
    log_bucket  = bool

    processing_queue = bool
    datalake_queue   = bool
    sns              = bool

    rds = bool

    ecs_cluster        = bool
    inbound_service    = bool
    outbound_service   = bool
    processor_service  = bool
    management_service = bool

    vpc_endpoints = object({
      s3              = bool
      ecr             = bool
      sqs             = bool
      kms             = bool
      logs            = bool
      sts             = bool
      secrets_manager = bool
    })
  })

  validation {
    condition     = var.deployment.app_az_count >= 1 && var.deployment.app_az_count <= 2
    error_message = "deployment.app_az_count must be 1 or 2."
  }

  validation {
    condition     = var.deployment.nat_az_count >= 0 && var.deployment.nat_az_count <= 2
    error_message = "deployment.nat_az_count must be 0, 1, or 2."
  }
}

# ============================================================
# ALB / CLOUDFRONT / DNS
# ============================================================


variable "inbound_blue_green_enabled" {
  description = "Enable native Amazon ECS blue/green deployments for the ALB-facing inbound service. Recommended for Production only."
  type        = bool
  default     = false
}

variable "inbound_blue_green_bake_time_minutes" {
  description = "Minutes to keep both inbound service revisions running after production traffic shifts to the green revision."
  type        = number
  default     = 10

  validation {
    condition     = var.inbound_blue_green_bake_time_minutes >= 0 && var.inbound_blue_green_bake_time_minutes <= 1440
    error_message = "inbound_blue_green_bake_time_minutes must be between 0 and 1440."
  }
}

variable "management_port" {
  description = "Management ECS container/target-group port."
  type        = number
  default     = 8090
}

variable "inbound_port" {
  description = "Inbound ECS container/target-group port."
  type        = number
  default     = 8080
}

variable "alb_certificate_arn" {
  description = "Regional ACM certificate ARN for HTTPS on the internal ALB. If null, ALB uses HTTP."
  type        = string
  default     = null
}

variable "alb_ingress_cidrs" {
  description = "Optional direct CIDRs allowed to reach the internal ALB when testing without CloudFront."
  type        = list(string)
  default     = []
}

variable "alb_health_check_path" {
  description = "Inbound service target-group health check path."
  type        = string
  default     = "/health"
}

variable "cloudfront_aliases" {
  description = "CloudFront aliases."
  type        = list(string)
  default     = []
}

variable "cloudfront_acm_certificate_arn" {
  description = "Optional existing ACM certificate ARN in us-east-1 for CloudFront aliases. When null and Route53 DNS is managed by this stack, Terraform can create and validate the certificate automatically."
  type        = string
  default     = null
  nullable    = true
}

variable "route53_zone_id" {
  description = "Optional existing public Route53 hosted-zone ID. When null, Terraform can create a public hosted zone if route53_zone_name is set."
  type        = string
  default     = null
  nullable    = true
}

variable "route53_zone_name" {
  description = "Optional public Route53 hosted-zone name, for example example.com. When deployment.route53=true and route53_zone_id is null, Terraform creates this hosted zone. Leave null when using only the default CloudFront domain."
  type        = string
  default     = null
  nullable    = true
}

# ============================================================
# ECS / ECR
# ============================================================

variable "container_image_tag" {
  description = "Container image tag. In CI/CD, use an immutable commit SHA or release tag."
  type        = string
  default     = "bootstrap"
}

variable "ecs_cpu" {
  description = "Fargate task CPU units."
  type        = number
  default     = 256
}

variable "ecs_memory" {
  description = "Fargate task memory MiB."
  type        = number
  default     = 512
}

variable "ecs_desired_count" {
  description = "Desired count by ECS service."
  type = object({
    inbound    = number
    outbound   = number
    processor  = number
    management = number
  })
  default = {
    inbound    = 1
    outbound   = 1
    processor  = 1
    management = 1
  }
}


variable "service_deployment_enabled" {
  description = "Master switch for ECS services. Set false during the first infrastructure/ECR bootstrap apply; normal CI/CD leaves this true."
  type        = bool
  default     = true
}

variable "meraki_base_url" {
  description = "Cisco Meraki Dashboard API base URL, or an approved mock/DevNet endpoint in lower environments."
  type        = string
  default     = "https://api.meraki.com/api/v1"
}

variable "meraki_poll_paths" {
  description = "Comma-separated Meraki API paths polled by the outbound service."
  type        = string
  default     = "/organizations"
}

variable "meraki_poll_interval_seconds" {
  description = "Outbound polling interval."
  type        = number
  default     = 300
}

variable "webhook_auth_required" {
  description = "Require X-Meraki-Secret on inbound webhook requests."
  type        = bool
  default     = true
}

variable "processor_poll_wait_seconds" {
  description = "SQS long-poll wait used by the processor."
  type        = number
  default     = 20
}

# ============================================================
# DATA / QUEUES / SNS
# ============================================================

variable "data_bucket_force_destroy" {
  description = "Allow Terraform to destroy non-empty data bucket. Keep false outside disposable environments."
  type        = bool
  default     = false
}

variable "log_bucket_force_destroy" {
  description = "Allow Terraform to destroy non-empty log bucket."
  type        = bool
  default     = false
}

variable "s3_data_retention_days" {
  description = "Lifecycle retention for noncurrent/expired data objects where applicable."
  type        = number
  default     = 90
}

variable "sqs_visibility_timeout_seconds" {
  description = "Visibility timeout for application queues."
  type        = number
  default     = 300
}

variable "sns_https_endpoints" {
  description = "Optional HTTPS endpoints subscribed to the ServiceNow notification SNS topic."
  type        = list(string)
  default     = []
}

# ============================================================
# RDS
# ============================================================

variable "rds_instance_class" {
  description = "PostgreSQL RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16"
}

variable "rds_database_name" {
  description = "PostgreSQL database name."
  type        = string
  default     = "occupancy"
}

variable "rds_username" {
  description = "RDS master username. Password is managed by RDS/Secrets Manager."
  type        = string
  default     = "platform_admin"
}

variable "rds_multi_az" {
  description = "Whether the RDS DB instance itself is Multi-AZ. The DB subnet group still spans two AZs."
  type        = bool
  default     = false
}

variable "rds_allocated_storage" {
  description = "Initial RDS allocated storage in GiB."
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "RDS storage autoscaling maximum in GiB."
  type        = number
  default     = 100
}

variable "rds_backup_retention_days" {
  description = "RDS automated backup retention."
  type        = number
  default     = 7
}

# ============================================================
# KMS / WAF
# ============================================================

variable "kms_key_deletion_window" {
  description = "KMS key deletion window in days."
  type        = number
  default     = 30
}

variable "waf_rate_limit" {
  description = "CloudFront WAF per-IP rate limit over the provider/WAF evaluation window."
  type        = number
  default     = 2000
}
