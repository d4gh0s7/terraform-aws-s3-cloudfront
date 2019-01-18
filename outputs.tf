output "AWS s3 bucket name" {
  value = "${aws_s3_bucket.deployment_bucket.bucket}"
}

output "AWS CloudFront distribution origin" {
  value = "${aws_cloudfront_distribution.deployment_cdn.origin}"
}

output "AWS CloudFront FQDN" {
  value = "${aws_cloudfront_distribution.deployment_cdn.domain_name}"
}

output "AWS CloudFront Distribution ID" {
  value = "${aws_cloudfront_distribution.deployment_cdn.id}"
}
