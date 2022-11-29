/**
 * # S3 Hosted Web Applications CSR
 * ----
 * Fully hosted on AWS with s3, cloudfront and route53
 */

locals {
  is_prod = var.environment == "prd"

  subdomain = local.is_prod ?  var.subdomain : fomart("%s.%s", var.subdomain, var.environment)
  bucket_name = format("%s.%s",local.subdomain,var.site_domain)

  files = fileset(format("%s/dist/",path.root), ".*")
}

resource "aws_s3_bucket" "site" {
  bucket = local.bucket_name
 }

resource "aws_s3_bucket_acl" "example_bucket_acl" {
  bucket = aws_s3_bucket.site.id
  acl    = "public-read"
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


# resource "aws_s3_bucket_object" "this" {
#   for_each = local.files
# bucket = aws_s3_bucket.site.id
# key = each.key
# source = each.value
# etag = filemd5(each.value)
# }

data "aws_iam_policy_document" "S3_read_files" {
  statement {
    sid = "CloudFrontOriginReadGetObject"
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = [ 
      aws_s3_bucket.site.arn,
      format("%s/*",aws_s3_bucket.site.arn)
    ]
    principals {
      type = "AWS"
      identifiers = [ aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn  ]
    }
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
}

resource "aws_s3_bucket_policy" "public_read" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.S3_read_files.json
}

resource "aws_acm_certificate" "cert" {
  domain_name               = format("%s.%s", local.subdomain, var.site_domain)
  validation_method         = "DNS"

  tags = {
    Name = var.site_domain
  }
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
    domain_name = aws_s3_bucket.site.bucket_domain_name
    origin_id   = aws_s3_bucket.site.id
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
    # custom_origin_config {
    ##   http_port              = "80"
    #   https_port             = "443"
    #   origin_protocol_policy = "https-only"
    #   origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    # }
  }
  enabled             = true
  default_root_object = "index.html"

  aliases = [
     format("%s.%s",local.subdomain,var.site_domain),
    #  var.site_domain,
  ]

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = aws_s3_bucket.site.id
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "allow-all"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.cert.certificate_arn
    ssl_support_method  = "sni-only"
  }
  provisioner "local-exec" {
    command = "aws cloudfront create-invalidation --distribution-id ${self.id} --paths '/*'"
  }
}

resource "aws_route53_record" "this" {
  zone_id = data.aws_route53_zone.domain.zone_id
  name    = local.subdomain
  ttl     = 1
  type    = "CNAME"

  records  = [aws_cloudfront_distribution.dist.domain_name]
}