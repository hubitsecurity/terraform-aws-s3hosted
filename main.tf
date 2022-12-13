/**
 * # S3 Hosted Web Applications CSR
 * ----
 * Fully hosted on AWS with s3, cloudfront and route53
 */

locals {
  is_prod = var.environment == "prd"

  subdomain   = local.is_prod ? var.subdomain : format("%s-%s", var.subdomain, var.environment)
  bucket_name = format("%s.%s", local.subdomain, var.site_domain)

  files = { for k, v in fileset(var.path_to_deploy_files, "*") : k => format("%s%s", var.path_to_deploy_files, v) }

  tags = var.tags
}

resource "aws_s3_bucket" "site" {
  bucket = local.bucket_name
  tags   = local.tags
}

# resource "aws_s3_bucket_acl" "example_bucket_acl" {
#   bucket = aws_s3_bucket.site.id
#   acl    = "public-read"
# }

resource "aws_s3_bucket_ownership_controls" "example" {
  bucket = aws_s3_bucket.site.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}


resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_website_configuration" "this" {
  bucket = aws_s3_bucket.site.bucket

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "index.html"
  }

  # routing_rule {
  # condition {
  #   key_prefix_equals = "docs/"
  # }
  # redirect {
  #   replace_key_prefix_with = "documents/"
  # }
  # }
}

resource "aws_s3_bucket_cors_configuration" "this" {
  bucket = aws_s3_bucket.site.id
  cors_rule {
    allowed_headers = [
      "*"
    ]
    allowed_methods = [
      "PUT",
      "POST",
      "DELETE",
      "GET",
      "HEAD"
    ]
    allowed_origins = [
      "https://${local.bucket_name}",
      "https://${aws_cloudfront_distribution.dist.domain_name}"
    ]
    expose_headers = [
      "ETag",
      "Access-Control-Allow-Origin",
      "Access-Control-Allow-Methods",
      "Access-Control-Allow-Headers",
      "Access-Control-Expose-Headers"
    ]
    max_age_seconds = 3000
  }

}

# resource "aws_s3_bucket_object" "this" {
#   for_each = local.files
#   bucket   = aws_s3_bucket.site.id
#   key      = each.key
#   source   = each.value
#   etag     = filemd5(each.value)
# }

data "aws_iam_policy_document" "S3_read_files" {
  statement {
    sid    = "CloudFrontDistReadGetObject"
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = [
        "cloudfront.amazonaws.com"
      ]
    }
    resources = [
      aws_s3_bucket.site.arn,
      format("%s/*", aws_s3_bucket.site.arn)
    ]

    actions = [
      "s3:GetObject"
    ]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.dist.arn]
    }
  }
}


resource "aws_cloudfront_origin_access_control" "origin_access_control" {
  name                              = "control-access-${var.subdomain}"
  description                       = "Control Origin for S3 for ${var.subdomain}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.S3_read_files.json
}

resource "aws_acm_certificate" "cert" {
  domain_name       = format("%s.%s", local.subdomain, var.site_domain)
  validation_method = "DNS"

  tags = merge(local.tags, {
    Name = var.site_domain
  })
}

data "aws_route53_zone" "domain" {
  name = format("%s.", var.site_domain)
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      record  = dvo.resource_record_value
      type    = dvo.resource_record_type
      zone_id = data.aws_route53_zone.domain.zone_id
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = each.value.zone_id
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]

}

resource "aws_cloudfront_distribution" "dist" {

  origin {
    domain_name              = aws_s3_bucket.site.bucket_domain_name
    origin_id                = aws_s3_bucket.site.id
    origin_access_control_id = aws_cloudfront_origin_access_control.origin_access_control.id
  }
  enabled             = true
  default_root_object = "index.html"

  aliases = [
    local.bucket_name,
  ]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  custom_error_response {
    error_caching_min_ttl = 10
    error_code            = 403
    response_code         = 403
    response_page_path    = "/"
  }

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.site.id

    origin_request_policy_id   = data.aws_cloudfront_origin_request_policy.this.id
    cache_policy_id            = data.aws_cloudfront_cache_policy.this.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this.id

    compress               = true
    viewer_protocol_policy = "redirect-to-https"

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method  = "sni-only"
  }
  tags = local.tags
}

data "aws_cloudfront_origin_request_policy" "this" {
  name = "Managed-CORS-S3Origin"
}

data "aws_cloudfront_cache_policy" "this" {
  name = "Managed-CachingOptimized"
}

resource "aws_cloudfront_response_headers_policy" "this" {
  name    = "request-headers-policy"
  comment = "Security Best Practices"
  security_headers_config {

    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }

    referrer_policy {
      override        = true
      referrer_policy = "strict-origin-when-cross-origin"
    }

    strict_transport_security {
      access_control_max_age_sec = 84200
      preload                    = true
      include_subdomains         = true
      override                   = true
    }

    xss_protection {
      mode_block = true
      override   = true
      protection = true
    }
  }

  cors_config {
    access_control_allow_credentials = false

    access_control_allow_headers {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["ALL"]
    }

    access_control_allow_origins {
      items = ["*"]
    }
    access_control_expose_headers {
      items = ["*"]
    }
    access_control_max_age_sec = 600

    origin_override = true
  }
}

resource "aws_route53_record" "this" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = local.subdomain
  ttl     = 1
  type    = "CNAME"

  records = [aws_cloudfront_distribution.dist.domain_name]
}