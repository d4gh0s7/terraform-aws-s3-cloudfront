variable "deployment_tag" {
  description = "A tag to identify the deployment accross the created resources"
  default     = "production"
  type        = "string"
}

variable "deployment_source_code_path" {
  description = "Path to the application code to be pushed to the s3 bucket, must end with a trailing slash"
  default     = "src/app/"
  type        = "string"
}

# AWS variables
variable "aws_region" {
  description = "the AWS region in which the application will be deployed."

  # eu-west-3 for Paris
  # eu-central-1 for Frankfurt
  # eu-west-1 for Ireland
  # eu-north-1 for Stockholm
  # default = "eu-west-3"
  default = "us-east-1"
}

# application variables
variable "application_root_domain" {
  description = "The application's root domain, must be handled by route53"
  type        = "string"
}

# AWS s3 variables
variable "aws_s3_bucket_name" {
  description = "The AWS s3 bucket name, must be a DNS valid format, matching the domain under wich the application will be served"
  type        = "string"
}

variable "aws_s3_bucket_enable_acceleration" {
  description = "true|false to enable the s3 transfer acceleration"
  default     = false
}

variable "aws_s3_origin_id" {
  description = "specify a unique id to bind the cloudfront distribution to the s3 bucket"
  default     = "webapp-S3-Origin"
  type        = "string"
}

variable "aws_s3_bucket_index_file" {
  description = "The file served as default by AWS s3 bucket"
  default     = "index.html"
  type        = "string"
}

variable "aws_s3_bucket_error_file" {
  description = "The file rendered when an exeception occures"
  default     = "error.html"
  type        = "string"
}

variable "aws_s3_enable_versioning" {
  description = "true|false to instruct the s3 bucket whether to keep versioning or not"
  default     = true
}

# AWS cloudfront variables
variable "aws_cloudfront_origin_access_identity_comment" {
  description = "Comment"
  default     = "webapp origin access identity"
}

variable "aws_cloudfront_distribution_comment" {
  description = "Cloudfront distribution description or notes"
  default     = "webapp cloudfront distribution"
  type        = "string"
}

variable "aws_cloudfront_enable_compression" {
  description = "true|false to instruct cloudfront whether to compress the http response or not"
  default     = true
}
