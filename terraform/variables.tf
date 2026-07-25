variable "aws_region" {
  description = "AWS region for the S3 origin bucket."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project name used in resource names and tags."
  type        = string
  default     = "static-site"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "production"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.environment))
    error_message = "environment must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "bucket_name" {
  description = "Globally unique name for the private S3 origin bucket."
  type        = string

  validation {
    condition = (
      length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.bucket_name))
    )
    error_message = "bucket_name must be a valid 3-63 character S3 bucket name."
  }
}

variable "force_destroy_bucket" {
  description = "Allow Terraform to delete the bucket and all object versions. Keep false in production."
  type        = bool
  default     = false
}

variable "github_repository" {
  description = "Exact GitHub owner/repository used in the OIDC sub claim."
  type        = string

  validation {
    condition     = can(regex("^[^/]+/.+$", var.github_repository))
    error_message = "github_repository must use the owner/repository format."
  }
}

variable "github_protected_branch" {
  description = "Protected GitHub branch allowed to assume the production deployment role."
  type        = string
  default     = "main"
}

variable "github_oidc_audience" {
  description = "Audience used by the GitHub Actions ID token and AWS IAM OIDC provider."
  type        = string
  default     = "sts.amazonaws.com"
}

variable "cloudfront_price_class" {
  description = "CloudFront edge-location price class."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition = contains(
      ["PriceClass_100", "PriceClass_200", "PriceClass_All"],
      var.cloudfront_price_class
    )
    error_message = "cloudfront_price_class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}

variable "additional_tags" {
  description = "Additional tags to apply to taggable resources."
  type        = map(string)
  default     = {}
}

