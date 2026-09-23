aws_region   = "eu-west-2"
environment  = "uat"
project_name = "occupancy-platform"
owner        = "platform-team"

# Terraform derives UAT as 10.0.16.0/21.
vpc_cidr = "10.0.0.0/16"

azs = [
  "eu-west-2a",
  "eu-west-2b"
]

deployment = {
  app_az_count = 2

  # Production-like topology. Set nat_az_count=1 only if TDA explicitly accepts
  # lower-cost cross-AZ NAT for UAT.
  nat_gateway  = true
  nat_az_count = 2

  alb        = true
  cloudfront = true
  waf        = true
  route53    = false

  ecr             = true
  kms             = true
  secrets_manager = true

  data_bucket = true
  log_bucket  = true

  processing_queue = true
  datalake_queue   = true
  sns               = true

  rds = true

  ecs_cluster       = true
  inbound_service   = true
  dashboard_sync_service  = false
  processor_service = true
  management_service = true

  vpc_endpoints = {
    s3   = true
    ecr  = true
    sqs  = true
    kms  = true
    logs            = true
    sts             = true
    secrets_manager = true
  }
}

# Replace before using HTTPS on the internal ALB.
# When null, CloudFront -> ALB uses HTTP inside the VPC origin.
alb_certificate_arn = null
alb_ingress_cidrs   = []

# Add aliases only after setting a valid us-east-1 ACM certificate.
cloudfront_aliases             = []
cloudfront_acm_certificate_arn = null
route53_zone_id                 = null
route53_zone_name               = null

rds_multi_az      = true
container_image_tag = "bootstrap"

# Application integration runtime. In lower environments this may point to an
# approved externally reachable mock/DevNet endpoint instead of production Meraki.
meraki_base_url                  = "https://api.meraki.com/api/v1"
meraki_poll_paths                = "/organizations"
meraki_poll_interval_seconds     = 300
webhook_auth_required            = true
processor_poll_wait_seconds      = 20
