data "aws_cloudfront_cache_policy" "caching_disabled" {
  count = var.deployment.cloudfront ? 1 : 0
  name  = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer" {
  count = var.deployment.cloudfront ? 1 : 0
  name  = "Managed-AllViewer"
}

resource "aws_cloudfront_vpc_origin" "alb" {
  count = var.deployment.cloudfront ? 1 : 0

  vpc_origin_endpoint_config {
    name                   = "${local.name_prefix}-alb-vpc-origin"
    arn                    = aws_lb.internal[0].arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = local.alb_origin_policy

    origin_ssl_protocols {
      quantity = 1
      items    = ["TLSv1.2"]
    }
  }

  tags = {
    Name = "${local.name_prefix}-cloudfront-vpc-origin"
  }
}

resource "aws_cloudfront_distribution" "api" {
  count = var.deployment.cloudfront ? 1 : 0

  enabled         = true
  is_ipv6_enabled = true
  comment         = "${local.name_prefix} REST API"
  aliases         = var.cloudfront_aliases
  price_class     = "PriceClass_100"

  origin {
    domain_name = aws_lb.internal[0].dns_name
    origin_id   = "${local.name_prefix}-internal-alb"

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.alb[0].id
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }
  }

  default_cache_behavior {
    target_origin_id       = "${local.name_prefix}-internal-alb"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled[0].id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer[0].id
  }

  viewer_certificate {
    cloudfront_default_certificate = local.cloudfront_certificate_arn == null
    acm_certificate_arn            = local.cloudfront_certificate_arn
    ssl_support_method             = local.cloudfront_certificate_arn != null ? "sni-only" : null
    minimum_protocol_version       = local.cloudfront_certificate_arn != null ? "TLSv1.2_2021" : null
  }

  web_acl_id = var.deployment.waf ? aws_wafv2_web_acl.cloudfront[0].arn : null

restrictions {
  geo_restriction {
    restriction_type = "whitelist"
    locations        = ["GB"]
  }
}

  tags = {
    Name = "${local.name_prefix}-cloudfront"
  }
}
