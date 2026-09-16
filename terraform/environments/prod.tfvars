aws_region   = "eu-west-2"
environment  = "prod"
project_name = "occupancy-pf"
owner        = "platform-team"

# Terraform derives Prod as 10.0.24.0/21.
# NAT allocation inside Prod is therefore 10.0.28.0/24,
# split to 10.0.28.0/25 and 10.0.28.128/25.
vpc_cidr = "10.0.0.0/16"

azs = [
  "eu-west-2a",
  "eu-west-2b"
]

deployment = {
  app_az_count = 2

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
  sns              = true

  rds = true

  ecs_cluster = true

  # Turn these on after the corresponding immutable container images exist.
  inbound_service    = false
  outbound_service   = false
  processor_service  = false
  management_service = false

  vpc_endpoints = {
    s3              = true
    ecr             = true
    sqs             = true
    kms             = true
    logs            = true
    sts             = true
    secrets_manager = true
  }
}

# For production, set this to the regional ACM ARN before enabling traffic.
alb_certificate_arn = null
alb_ingress_cidrs   = []

# Example after certificate/DNS approval:
# cloudfront_aliases             = ["api.example.com"]
# cloudfront_acm_certificate_arn = "arn:aws:acm:us-east-1:..."
# route53_zone_id                = "Z..."
cloudfront_aliases             = []
cloudfront_acm_certificate_arn = null
route53_zone_id                = null
route53_zone_name              = null

# Production uses native ECS blue/green for the ALB-facing inbound service.
# Blue and green revisions share the same cluster, APP subnets, ALB, CloudFront and WAF.
inbound_blue_green_enabled           = true
inbound_blue_green_bake_time_minutes = 10

rds_multi_az        = true
container_image_tag = "bootstrap"

# Application integration runtime. In lower environments this may point to an
# approved externally reachable mock/DevNet endpoint instead of production Meraki.
meraki_base_url              = "https://api.meraki.com/api/v1"
meraki_poll_paths            = "/organizations"
meraki_poll_interval_seconds = 300
webhook_auth_required        = true
processor_poll_wait_seconds  = 20
