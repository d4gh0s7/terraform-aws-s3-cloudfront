terraform {
  backend "s3" {
    bucket = "hyperd-sh-terraform-remote-store"
    key    = "terraform.tfstate"
    region = "eu-central-1"
  }
}

provider "aws" {
  region                  = "${var.aws_region}"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "default"
}

locals {
  s3_origin_id = "${var.aws_s3_origin_id}"
}

data "aws_route53_zone" "deployment_zone" {
  name         = "${var.application_root_domain}."
  private_zone = false
}

##### AWS s3 bucket:START

# create a log bucket
resource "aws_s3_bucket" "log_bucket" {
  bucket = "${var.aws_s3_bucket_name}-log-bucket"
  acl    = "log-delivery-write"

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule {
    id      = "s3_log"
    enabled = true

    prefix = "s3-log/"

    tags = {
      "rule"      = "log"
      "autoclean" = "true"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA" # or "ONEZONE_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER"
    }

    expiration {
      days = 90
    }
  }

  lifecycle_rule {
    id      = "cloudfront_log"
    enabled = true

    prefix = "cloudfront-log/"

    tags = {
      "rule"      = "log"
      "autoclean" = "true"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA" # or "ONEZONE_IA"
    }

    transition {
      days          = 60
      storage_class = "GLACIER"
    }

    expiration {
      days = 90
    }
  }
}

# resource for the S3 bucket the application will use.
resource "aws_s3_bucket" "deployment_bucket" {
  # NOTE: S3 bucket names must be unique across _all_ AWS accounts
  bucket = "${var.aws_s3_bucket_name}"

  #acceleration_status = "${var.aws_s3_bucket_enable_acceleration ? "Enabled" : "Suspended"}"
  # acceleration_status = "Suspended"
  acl = "private"

  force_destroy = false

  website {
    index_document = "${var.aws_s3_bucket_index_file}"
    error_document = "${var.aws_s3_bucket_error_file}"
  }

  versioning {
    enabled = "${var.aws_s3_enable_versioning}"
  }

  lifecycle_rule {
    prefix  = "/"
    enabled = true

    noncurrent_version_transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    noncurrent_version_transition {
      days          = 60
      storage_class = "GLACIER"
    }

    noncurrent_version_expiration {
      days = 90
    }
  }

  logging {
    target_bucket = "${aws_s3_bucket.log_bucket.id}"
    target_prefix = "s3-log/"
  }

  tags = {
    Name = "${var.deployment_tag}"
  }
}

# resource for the origin access identity cloudfront will use to access the s3 bucket.
resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "${var.aws_cloudfront_origin_access_identity_comment}"
}

# set up the IAM policy to grant the cloudfront distribution
# read-only access to the application's bucket.
data "aws_iam_policy_document" "cloudfront_origin" {
  statement {
    actions = ["s3:GetObject"]

    resources = ["arn:aws:s3:::${var.aws_s3_bucket_name}/*"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.aws_s3_bucket_name}"]

    principals {
      type        = "AWS"
      identifiers = ["${aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn}"]
    }
  }
}

# generate the bucket's ACL template file
data "template_file" "default_acl" {
  template = "${data.aws_iam_policy_document.cloudfront_origin.json}"

  vars {
    origin_path = "/"
    bucket_name = "${var.aws_s3_bucket_name}"
  }
}

resource "aws_s3_bucket_policy" "default_acl" {
  bucket = "${var.aws_s3_bucket_name}"
  policy = "${data.template_file.default_acl.rendered}"

  depends_on = ["aws_s3_bucket.deployment_bucket"]
}

resource "aws_s3_bucket_object" "s3_placeholder_page" {
  bucket                 = "${var.aws_s3_bucket_name}"
  key                    = "index.html"
  source                 = "${var.deployment_source_code_path}/index.html"
  content_type           = "text/html"
  server_side_encryption = "AES256"

  depends_on = ["aws_s3_bucket.deployment_bucket"]
}

resource "null_resource" "deploy_application" {
  provisioner "local-exec" {
    command = "aws s3 sync ${var.deployment_source_code_path}/ s3://${var.aws_s3_bucket_name} --exclude index.html --exclude *.tmp --exclude .DS_Store"
  }

  depends_on = ["aws_s3_bucket.deployment_bucket"]
}

##### AWS s3 bucket:END

##### AWS ACM certificate:START
resource "aws_acm_certificate" "cert" {
  domain_name               = "${var.application_root_domain}"
  subject_alternative_names = ["www.${var.application_root_domain}"]
  validation_method         = "DNS"
}

resource "aws_route53_record" "cert_validation" {
  name    = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_type}"
  zone_id = "${data.aws_route53_zone.deployment_zone.id}"
  records = ["${aws_acm_certificate.cert.domain_validation_options.0.resource_record_value}"]
  ttl     = 60

  depends_on = ["aws_acm_certificate.cert"]
}

resource "aws_route53_record" "cert_validation_alt" {
  name    = "${aws_acm_certificate.cert.domain_validation_options.1.resource_record_name}"
  type    = "${aws_acm_certificate.cert.domain_validation_options.1.resource_record_type}"
  zone_id = "${data.aws_route53_zone.deployment_zone.id}"
  records = ["${aws_acm_certificate.cert.domain_validation_options.1.resource_record_value}"]
  ttl     = 60

  depends_on = ["aws_acm_certificate.cert"]
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn = "${aws_acm_certificate.cert.arn}"

  validation_record_fqdns = [
    "${aws_route53_record.cert_validation.fqdn}",
    "${aws_route53_record.cert_validation_alt.fqdn}",
  ]

  depends_on = ["aws_route53_record.cert_validation", "aws_route53_record.cert_validation_alt"]
}

##### AWS ACM certificate:END

##### AWS Cloudfront:START

# resource for the cloudfront distribution that will server the application
resource "aws_cloudfront_distribution" "deployment_cdn" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.aws_cloudfront_distribution_comment}"
  default_root_object = "${var.aws_s3_bucket_index_file}"
  price_class         = "PriceClass_200"
  retain_on_delete    = true

  origin {
    domain_name = "${aws_s3_bucket.deployment_bucket.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"

    s3_origin_config {
      origin_access_identity = "${aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path}"
    }
  }

  logging_config {
    include_cookies = true
    bucket          = "${aws_s3_bucket.log_bucket.bucket_domain_name}"
    prefix          = "cloudfront-log/"
  }

  aliases = ["${var.application_root_domain}", "www.${var.application_root_domain}"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    compress         = true
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = true
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    lambda_function_association {
      event_type = "viewer-request"

      # lambda_arn   = "arn:aws:lambda:us-east-1:700029131908:function:hyperd-cloudfront-redirections:4"
      lambda_arn   = "arn:aws:lambda:us-east-1:700029131908:function:spaRouter:1"
      include_body = false
    }

    lambda_function_association {
      event_type = "origin-response"

      # lambda_arn   = "arn:aws:lambda:us-east-1:700029131908:function:hyperd-cloudfront-redirections:4"
      lambda_arn   = "arn:aws:lambda:us-east-1:700029131908:function:securityHeaderInjector:8"
      include_body = false
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 3600
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "blacklist"
      locations        = ["CN"]
    }
  }

  tags = {
    environment = "${var.deployment_tag}"
  }

  viewer_certificate {
    cloudfront_default_certificate = "${aws_acm_certificate.cert.arn == "" ? true : false}"
    acm_certificate_arn            = "${aws_acm_certificate.cert.arn}"
    ssl_support_method             = "sni-only"
    minimum_protocol_version       = "TLSv1.2_2018"
  }

  depends_on = ["aws_s3_bucket.deployment_bucket", "aws_acm_certificate_validation.cert"]
}

##### AWS Cloudfront:END

##### AWS route53 record:START

# resource for the route53 alias to correctly resolve the cloudfront distribution
# with the application's domain name.
resource "aws_route53_record" "deployment_cdn_zone_canonical" {
  zone_id = "${data.aws_route53_zone.deployment_zone.id}"
  name    = "www.${var.application_root_domain}"
  type    = "A"

  alias {
    name                   = "${aws_cloudfront_distribution.deployment_cdn.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.deployment_cdn.hosted_zone_id}"
    evaluate_target_health = false
  }

  depends_on = ["aws_cloudfront_distribution.deployment_cdn"]
}

resource "aws_route53_record" "deployment_cdn_zone_www" {
  zone_id = "${data.aws_route53_zone.deployment_zone.id}"
  name    = "${var.application_root_domain}"
  type    = "A"

  alias {
    name                   = "${aws_cloudfront_distribution.deployment_cdn.domain_name}"
    zone_id                = "${aws_cloudfront_distribution.deployment_cdn.hosted_zone_id}"
    evaluate_target_health = false
  }

  depends_on = ["aws_cloudfront_distribution.deployment_cdn"]
}

##### AWS route53 record:END

