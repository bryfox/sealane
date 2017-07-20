variable "hostname" {
  description = <<EOS
      Base hostname for the static site.
      Used for the name of the S3 bucket and cloudfront subdomain.

      Example: www.example.com
EOS
}

variable "ssl_cert_arn" {
  description = <<EOS
    ARN for cert created with AWS cli/gui
      You'll first need to provision an SSL cert and make it available to the AWS
      Certificate Manager. To request a free cert, visit https://console.aws.amazon.com/acm/home.
      This process will take some time as you'll need to prove domain ownership.
      Docs: https://docs.aws.amazon.com/acm/latest/userguide/gs-acm-request.html

      Example: arn:aws:acm:us-east-1:xxxxxxxxxxxx:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
EOS
}

variable "logging_bucket" {
  description = <<EOS
    S3 Bucket for log storage

    Logs will be added in a directory named after the hostname, so you can have a single logging bucket for multiple sites.

    To disable logging, set this to "" and remove the "logging_config" resource in the static.tf config for cloudfront

    Example: mycompanylogs
EOS
}

variable "aws_region"       { default = "us-east-1" description = "S3 buckets are region-specific" }
variable "aws_cli_profile"  { default = "default" description = "Profile name in .aws/credentials" }
variable "environment_name" { default = "production" description = "For tagging" }

# DNS config: short times for initial development
variable "use_short_ttl" { default = true type = "" description = "Probably set to false once initial development stabilizes" }
# gzip for Cloudfront
variable "enable_gzip" { default = true }

provider "aws" {
  region  = "${var.aws_region}"
  # load creds from ~/.aws/credentials, and use ${profile} profile
  profile = "${var.aws_cli_profile}"
}

# S3 Static Site
# The bucket policy allows read access to contents, even with the private ACL.
# Changing the ACL to "public-read" would also allow anyone to list the bucket contents.
resource "aws_s3_bucket" "website" {
  bucket = "${var.hostname}"
  acl    = "private"

  policy = <<POLICY
{
  "Version":"2012-10-17",
  "Statement":[{
    "Sid":"PublicReadForGetBucketObjects",
    "Effect":"Allow",
    "Principal": "*",
    "Action":["s3:GetObject"],
    "Resource":["arn:aws:s3:::${var.hostname}/*"]
  }]
}
POLICY

  tags {
    Environment = "${var.environment_name}"
  }

  website {
    index_document = "index.html"
    error_document = "404.html"
  }
}

# S3 logs
resource "aws_s3_bucket" "websitelogs" {
  # Skip this resource if logging_bucket is empty.
  # Note: you'll also need to remove logging_config from the cloudfront resource.
  count  = "${var.logging_bucket == "" ? 0 : 1}"
  bucket = "${var.logging_bucket}"
  acl    = "private"

  tags {
    Environment = "${var.environment_name}"
  }
}

# Cloudfront CDN for site
# See also https://www.terraform.io/docs/providers/aws/r/cloudfront_distribution.html#logging-config-arguments
# - SSL from edge to clients
# - http internally
# - support index documents at all levels (subdirectories)
resource "aws_cloudfront_distribution" "cdn" {
  depends_on = ["aws_s3_bucket.website"]

  origin {
    origin_id   = "website_bucket_origin"

    # Configure this origin as a web site, not an S3 bucket, so that we get support for
    # index objects at all levels. Use the region-specific URL to support this.
    domain_name = "${var.hostname}.s3-website-${var.aws_region}.amazonaws.com"

    # And this is all required since we're telling cloudfront to use the origin as a website
    # (again, not as an S3 bucket)
    # See https://groups.google.com/forum/#!topic/terraform-tool/JSOhKDXNaYI
    custom_origin_config {
      # s3-as-website only supports "http-only"
      # http://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/distribution-web-values-specify.html#DownloadDistValuesOriginProtocolPolicy
      origin_protocol_policy = "http-only"
      http_port              = 80
      https_port             = 443
      origin_ssl_protocols   = ["TLSv1.2", "TLSv1.1", "TLSv1"]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.hostname}"

  # Probably don't need this with origin in web backend (not s3) mode
  default_root_object = "index.html"

  # Probably don't need this with origin in web backend (not s3) mode
  custom_error_response {
    error_code = 404
    response_page_path = "/404.html"
    response_code = 404
  }

  logging_config {
    include_cookies = false
    bucket          = "${aws_s3_bucket.websitelogs.bucket_domain_name}"
    prefix          = "${var.hostname}"
  }

  aliases = ["${var.hostname}"]

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "website_bucket_origin"
    compress         = "${var.enable_gzip}"

    # Static site: forward nothing
    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = "${var.use_short_ttl ? 0 : 0 }"
    default_ttl            = "${var.use_short_ttl ? 300 : 3600 }"
    max_ttl                = "${var.use_short_ttl ? 300 : 86400 }"
  }

  # [cheapest pricing is 100](https://aws.amazon.com/cloudfront/pricing/)
  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags {
    Environment = "${var.environment_name}"
  }

  viewer_certificate {
    # Created in web console; no terraform support yet
    acm_certificate_arn = "${var.ssl_cert_arn}"
    ssl_support_method = "sni-only"
    # TLSv1 required for SNI
    minimum_protocol_version = "TLSv1"
  }
}
