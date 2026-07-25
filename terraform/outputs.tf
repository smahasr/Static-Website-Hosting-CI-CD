output "aws_account_id" {
  description = "AWS account in which the stack was created."
  value       = data.aws_caller_identity.current.account_id
}

output "s3_bucket_name" {
  description = "Private S3 origin bucket."
  value       = aws_s3_bucket.site.id
}

output "s3_bucket_arn" {
  description = "ARN of the private S3 origin bucket."
  value       = aws_s3_bucket.site.arn
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID used by the deployment pipeline."
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution hostname."
  value       = aws_cloudfront_distribution.site.domain_name
}

output "site_url" {
  description = "Public HTTPS URL for the static application."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "cloudfront_oac_id" {
  description = "CloudFront Origin Access Control ID."
  value       = aws_cloudfront_origin_access_control.site.id
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions IAM OIDC provider."
  value       = aws_iam_openid_connect_provider.github.arn
}

output "github_deployment_role_arn" {
  description = "Role ARN to store in the GitHub Actions AWS_ROLE_ARN variable."
  value       = aws_iam_role.github_deploy.arn
}

output "github_actions_variables" {
  description = "Non-secret values to configure as GitHub Actions repository variables."
  value = {
    AWS_REGION                 = var.aws_region
    AWS_ROLE_ARN               = aws_iam_role.github_deploy.arn
    S3_BUCKET                  = aws_s3_bucket.site.id
    CLOUDFRONT_DISTRIBUTION_ID = aws_cloudfront_distribution.site.id
    SITE_URL                   = "https://${aws_cloudfront_distribution.site.domain_name}"
  }
}

