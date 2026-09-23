# Route53 is optional. Three supported modes:
# 1. route53=false: no Route53 resources. CloudFront can use its default domain.
# 2. route53=true + route53_zone_id set: use an existing public hosted zone.
# 3. route53=true + route53_zone_id=null + route53_zone_name set: create the public hosted zone.
#
# Creating a hosted zone does NOT register a domain. If Terraform creates the zone,
# delegate the registered domain/subdomain to the output name servers.

resource "aws_route53_zone" "public" {
  count = (
    var.deployment.route53 &&
    var.route53_zone_id == null &&
    var.route53_zone_name != null
  ) ? 1 : 0

  name    = trimsuffix(var.route53_zone_name, ".")
  comment = "Public hosted zone for ${local.name_prefix}"

  tags = {
    Name = "${local.name_prefix}-public-zone"
  }
}

locals {
  route53_effective_zone_id = var.deployment.route53 ? (
    var.route53_zone_id != null
    ? var.route53_zone_id
    : try(aws_route53_zone.public[0].zone_id, null)
  ) : null
}

resource "aws_route53_record" "cloudfront_a" {
  for_each = (
    var.deployment.route53 &&
    var.deployment.cloudfront &&
    local.route53_effective_zone_id != null
  ) ? toset(var.cloudfront_aliases) : toset([])

  zone_id = local.route53_effective_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.api[0].domain_name
    zone_id                = aws_cloudfront_distribution.api[0].hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_aaaa" {
  for_each = (
    var.deployment.route53 &&
    var.deployment.cloudfront &&
    local.route53_effective_zone_id != null
  ) ? toset(var.cloudfront_aliases) : toset([])

  zone_id = local.route53_effective_zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.api[0].domain_name
    zone_id                = aws_cloudfront_distribution.api[0].hosted_zone_id
    evaluate_target_health = false
  }
}
