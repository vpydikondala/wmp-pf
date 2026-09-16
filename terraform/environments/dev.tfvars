aws_region   = "eu-west-2"
environment  = "dev"
project_name = "occupancy-pf"
owner        = "platform-team"

# Same parent /16 for every environment.
# Terraform derives Dev as 10.0.0.0/21.
vpc_cidr = "10.0.0.0/16"

azs = [
  "eu-west-2a",
  "eu-west-2b"
]

deployment = {
  app_az_count = 2

  nat_gateway  = true
  nat_az_count = 1

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

  ecs_cluster        = false
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

alb_certificate_arn = null
alb_ingress_cidrs   = []

cloudfront_aliases             = []
cloudfront_acm_certificate_arn = null
route53_zone_id                = null
route53_zone_name              = null

rds_multi_az = false

# In CI/CD replace with the immutable image tag/SHA built for this release.
container_image_tag = "bootstrap"

# Application integration runtime. In lower environments this may point to an
# approved externally reachable mock/DevNet endpoint instead of production Meraki.
meraki_base_url              = "https://api.meraki.com/api/v1"
meraki_poll_paths            = "/organizations"
meraki_poll_interval_seconds = 300
webhook_auth_required        = true
processor_poll_wait_seconds  = 20
