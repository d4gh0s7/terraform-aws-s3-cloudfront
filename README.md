# WebApp Boilerplate

This **terraform** deployment is meant to wrap a static webapp / frontend skeleton around its own infrastructure logic over **AWS**

## Requirements

- [Terraform](https://terraform.io/)
- [python](https://www.python.org/downloads/)
- [pip](https://pypi.org/project/pip/)
- [jq](https://stedolan.github.io/jq/)
- [awscli](https://aws.amazon.com/cli/)

## Terraform Backend

The project can be executed on a local machine as well as in the cloud. In order to obtain the exepcted results in a consistent way, the terraform backend has been set to store the **state** remotely, to a AWS s3 bucket - ref [stack.tf](stack.tf).

```hlc
terraform {
  backend "s3" {
    bucket = "terraform-remote-store"
    key    = "terraform.tfstate"
    region = "eu-central-1"
  }
}
```

To set up your own terraform environment with the same logic, create a s3 bucket enabling **versioning** and **SSE** and grant your IAM User the following actions:

- s3:ListBucket
- s3:GetObject
- s3:PutObjec

An example is listed in the example below:

```json
{
  "Version": "2012-10-17",
  "Id": "Policy1234567891011",
  "Statement": [
    {
      "Sid": "Stmt1234567891011",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::1234567891011:user/deployment-operations"
      },
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::terraform-remote-store"
    },
    {
      "Sid": "Stmt12345678970543",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::1234567891011:user/deployment-operations"
      },
      "Action": ["s3:GetObject", "s3:PutObject"],
      "Resource": "arn:aws:s3:::terraform-remote-store/*"
    }
  ]
}
```

## Deployment polocy variables

The deployment policy variables are stored in `./src/.deployment_policy.json`.

- `source_code_path` is a pointer to the deployment files folder.
- `tag` is meant to group the deployment in order to monitor the costs or facilitate a bulk removal in case of failure.
- `root_domain` and the `s3_bucket_name` will form the domain seved through cloudfront in the form `s3_bucket_name`.`root_domain`.

```json
{
  "Version": "2018-12-27",
  "Deployment": [
    {
      "source_code_path": "./src/app",
      "tag": "production"
    }
  ],
  "Application": [
    {
      "root_domain": "domain.ext"
    }
  ],
  "AWS": [
    {
      "s3_bucket_name": "your-bucket-name"
    }
  ]
}
```

## Terraform Variables

```hlc
# can be overridden with .deployment_policy.json when executed through the gitlab pipeline
variable "deployment_tag" {
  description = "A tag to identify the deployment accross the created resources"
  default     = "production"
  type        = "string"
}

# can be overridden with .deployment_policy.json when executed through the gitlab pipeline
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
  default = "us-east-1"

  # default = "eu-west-3"
}

# application variables
# can be overridden with .deployment_policy.json when executed through the gitlab pipeline
variable "application_root_domain" {
  description = "The application's root domain, must be handled by route53"

  # default = "domain.ext"
  type = "string"
}

# AWS s3 variables
# can be overridden with .deployment_policy.json when executed through the gitlab pipeline
variable "aws_s3_bucket_name" {
  description = "The AWS s3 bucket name, must be a DNS valid format, matching the domain under wich the application will be served"
  type        = "string"
}

variable "aws_s3_bucket_enable_acceleration" {
  description = "true|false to enable the s3 transfer acceleration"
  default     = true
}

variable "aws_s3_origin_id" {
  description = "specify a unique id to bind the cloudfront distribution to the s3 bucket"
  default     = "web-app-S3-Origin"
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
```

## Run it

Despite the main goal of running this deployment through a gitlab-ci pipeline **ref:** [`.gitlab-ci.yml`](.gitlab-ci.yml), the code can be executed in many different ways. For instance by running the `deploy_stack` script in a terminal as follows:

```bash
git clone https://github.com/d4gh0s7/terraform-aws-s3-cloudfront.git && cd terraform-aws-s3-cloudfront

shasum -a512 -c deploy_stack_sha512sum # expect 'deploy_stack: OK' or do NOT run the next commands

chmod 0750 deploy_stack

./deploy_stack
```

Or command by command as described below:

```bash
git clone https://github.com/d4gh0s7/terraform-aws-s3-cloudfront.git && cd terraform-aws-s3-cloudfront

export application_root_domain=$(cat ./src/.deployment_policy.json |jq -r '.Application | .[].root_domain')

export deployment_tag=$(cat ./src/.deployment_policy.json |jq -r '.Deployment | .[].tag')

export deployment_source_code_path=$(cat ./src/.deployment_policy.json |jq -r '.Deployment | .[].source_code_path')

export aws_s3_bucket_name=$(cat ./src/.deployment_policy.json |jq -r '.AWS | .[].s3_bucket_name')

terraform init -input=false -force-copy

terraform plan \
    -var "application_root_domain=$application_root_domain" \
    -var "aws_s3_bucket_name=$aws_s3_bucket_name" \
    -var "deployment_source_code_path=$deployment_source_code_path" \
    -var "deployment_tag=$deployment_tag" -out "planfile"

terraform apply -input=false -auto-approve "planfile"
```

## License

CC0 1.0

## Author Information

[Francesco Cosentino](https://www.linkedin.com/in/francesco-cosentino/) - <fc@hyperd.sh>
