# CloudFront custom-domain certificates must be created in us-east-1.
# If an existing ARN is supplied, Terraform uses it. Otherwise, when aliases and
# a Route53 hosted zone are available, Terraform creates and DNS-validates one.

locals {
  create_cloudfront_certificate = (
    var.deployment.cloudfront &&
    length(var.cloudfront_aliases) > 0 &&
    var.cloudfront_acm_certificate_arn == null &&
    var.deployment.route53 &&
    local.route53_effective_zone_id != null
  )
}

resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1
  count    = local.create_cloudfront_certificate ? 1 : 0

  domain_name               = var.cloudfront_aliases[0]
  subject_alternative_names = slice(var.cloudfront_aliases, 1, length(var.cloudfront_aliases))
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-cloudfront-certificate"
  }
}

resource "aws_route53_record" "cloudfront_certificate_validation" {
  for_each = local.create_cloudfront_certificate ? {
    for dvo in aws_acm_certificate.cloudfront[0].domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id         = local.route53_effective_zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.us_east_1
  count    = local.create_cloudfront_certificate ? 1 : 0

  certificate_arn = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [
    for record in aws_route53_record.cloudfront_certificate_validation : record.fqdn
  ]
}

locals {
  cloudfront_certificate_arn = (
    var.cloudfront_acm_certificate_arn != null
    ? var.cloudfront_acm_certificate_arn
    : try(aws_acm_certificate_validation.cloudfront[0].certificate_arn, null)
  )
}
