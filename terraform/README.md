# Reusable Static Website Infrastructure

This Terraform configuration creates a secure static website deployment
platform using:

- A private, encrypted, and versioned Amazon S3 origin
- Amazon CloudFront with Origin Access Control
- HTTPS redirection, compression, caching, and managed security headers
- GitHub Actions OIDC authentication
- A repository- and branch-restricted IAM deployment role
- Least-privilege S3 upload and CloudFront invalidation permissions

It is intended for creating new deployments in fresh environments. If any
resources already exist, import them before applying the configuration.

## Architecture

```text
GitHub Actions
   |
   | OIDC ID token
   v
AWS STS -> Least-Privilege IAM Role
   |
   | aws s3 sync
   v
Private Amazon S3
   |
   | Signed OAC requests
   v
Amazon CloudFront -> HTTPS -> Browser
```

## Files

```text
terraform/
├── provider.tf
├── variables.tf
├── s3.tf
├── cloudfront.tf
├── iam.tf
├── outputs.tf
├── terraform.tfvars.example
├── .terraform.lock.hcl
└── README.md
```

## Prerequisites

- Terraform `1.15.x`
- An AWS account and credentials with permission to create S3, CloudFront, and
  IAM resources
- A GitHub repository
- A protected production branch, normally `main`

Find the exact `owner/repository` path in the repository's GitHub URL.

Do not put AWS access keys, GitHub tokens, or other secrets in `.tf` or
`.tfvars` files.

## 1. Configure variables

Copy the example:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Replace every `REPLACE_WITH_...` placeholder.

Example:

```hcl
aws_region   = "us-east-1"
project_name = "company-website"
environment  = "production"

bucket_name = "company-website-prod-123456789012"

github_repository = "company/company-website"

github_protected_branch = "main"
github_oidc_audience    = "sts.amazonaws.com"

cloudfront_price_class = "PriceClass_100"
force_destroy_bucket   = false

additional_tags = {
  Owner      = "platform-team"
  Repository = "https://github.com/company/company-website"
}
```

S3 bucket names are globally unique. Use lowercase letters, numbers, periods,
and hyphens only.

## 2. Authenticate to AWS

Use an AWS profile, environment credentials, AWS IAM Identity Center, or an
approved role.

Example with a named profile:

```bash
export AWS_PROFILE="your-profile"
export AWS_REGION="us-east-1"
aws sts get-caller-identity
```

Never commit local AWS credential files.

## 3. Initialize and validate

```bash
terraform init
terraform fmt -check
terraform validate
```

`terraform init` uses the committed `.terraform.lock.hcl` to install the same
AWS provider version used during validation.

## 4. Review the plan

```bash
terraform plan -out=tfplan
```

Review every create, update, replacement, and deletion. A new environment
should show new infrastructure being created. Stop if Terraform proposes
changing unrelated resources.

The saved `tfplan` file can contain infrastructure details and must not be
committed.

## 5. Apply

```bash
terraform apply tfplan
```

CloudFront creation can take several minutes. Terraform waits until the
distribution is deployed.

## 6. Configure GitHub Actions variables

Display the generated values:

```bash
terraform output github_actions_variables
```

Create these GitHub Actions repository variables under **Settings -> Secrets
and variables -> Actions -> Variables**:

```text
AWS_REGION
AWS_ROLE_ARN
S3_BUCKET
CLOUDFRONT_DISTRIBUTION_ID
SITE_URL
```

Do not create permanent `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`
secrets. GitHub Actions receives temporary AWS credentials through OIDC.

The deploy job must request an ID token with the same audience the AWS OIDC
provider trusts (the default used by `aws-actions/configure-aws-credentials`
is already `sts.amazonaws.com`):

```yaml
permissions:
  id-token: write
  contents: read
```

## 7. Deploy the application

After configuring the GitHub Actions variables:

1. Push application changes to GitHub.
2. Allow validation and packaging to finish.
3. Merge the pull request into the protected production branch.
4. Approve the `production` environment when the `deploy` job requests it.
5. Wait for S3 synchronization and CloudFront invalidation.
6. Confirm the verification job succeeds.

## 8. Verify the infrastructure

Get the site URL:

```bash
terraform output -raw site_url
```

Test CloudFront:

```bash
curl -I "$(terraform output -raw site_url)"
```

Expected result: `200`.

Confirm direct S3 access is blocked:

```bash
curl -o /dev/null -s -w '%{http_code}\n' \
  "https://$(terraform output -raw s3_bucket_name).s3.${AWS_REGION}.amazonaws.com/index.html"
```

Expected result after application deployment: `403`.

## Existing GitHub Actions OIDC provider

An AWS account can already contain the
`token.actions.githubusercontent.com` OIDC provider. This configuration
currently manages that provider as:

```text
aws_iam_openid_connect_provider.github
```

If it already exists, import it before planning:

```bash
terraform import \
  aws_iam_openid_connect_provider.github \
  "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
```

Run `terraform plan` again and confirm Terraform does not propose replacing the
provider.

## Existing infrastructure

Do not apply this configuration directly over manually created infrastructure.
Import each existing resource into its matching Terraform address first.

Common resource addresses include:

```text
aws_s3_bucket.site
aws_s3_bucket_ownership_controls.site
aws_s3_bucket_public_access_block.site
aws_s3_bucket_versioning.site
aws_s3_bucket_server_side_encryption_configuration.site
aws_s3_bucket_policy.cloudfront_origin
aws_cloudfront_origin_access_control.site
aws_cloudfront_distribution.site
aws_iam_openid_connect_provider.github
aws_iam_role.github_deploy
aws_iam_role_policy.github_deploy
```

After importing, run `terraform plan` and reconcile any differences before
applying.

## Team state management

Terraform uses local state unless a remote backend is configured. Local state
is acceptable only for isolated testing.

For shared production management, create a separate Terraform state bucket and
configure an S3 backend with encryption, versioning, restricted access, and
native locking:

```hcl
terraform {
  backend "s3" {
    bucket       = "company-terraform-state"
    key          = "static-site/production/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

The state bucket must exist before `terraform init` and must not be the website
content bucket created by this stack.

Never commit:

```text
.terraform/
terraform.tfstate
terraform.tfstate.*
terraform.tfvars
*.tfplan
crash.log
```

Terraform state can contain sensitive infrastructure data. Restrict access to
the backend bucket.

## Updating provider versions

The AWS provider is constrained to major version 6.

Review upgrades before changing the lock file:

```bash
terraform init -upgrade
terraform validate
terraform plan
```

Commit `.terraform.lock.hcl` only after reviewing and validating the new
provider selection.

## Destroying a test environment

Destruction is intentionally restricted:

```hcl
force_destroy_bucket = false
```

With this setting, Terraform cannot delete a non-empty or versioned bucket.

For a disposable test environment only:

1. Confirm that all objects and versions may be permanently deleted.
2. Set `force_destroy_bucket = true`.
3. Review `terraform plan`.
4. Run:

```bash
terraform destroy
```

Never enable forced bucket deletion casually in production.

## Troubleshooting

| Problem | Check |
|---|---|
| Bucket name already exists | Choose another globally unique bucket name |
| OIDC provider already exists | Import the existing `token.actions.githubusercontent.com` provider |
| STS denies role assumption | Verify the repository path, audience, and protected branch |
| S3 deployment is denied | Verify the generated role ARN and bucket variable |
| CloudFront returns `403` | Deploy `index.html` and verify OAC/bucket policy |
| Direct S3 access returns `200` | Confirm all four public-access blocks remain enabled |
| Old content remains visible | Run a CloudFront `/*` invalidation |
| State is locked | Confirm no apply is running before removing a stale lock |

## Security defaults

- S3 public access is completely blocked.
- S3 Object Ownership is bucket-owner enforced.
- S3 versioning and SSE-S3 encryption are enabled.
- CloudFront signs S3 requests using OAC and SigV4.
- HTTP viewers are redirected to HTTPS.
- Managed security headers are attached.
- GitHub Actions assumes a one-hour IAM role through OIDC.
- Trust is restricted to one repository and protected branch.
- Deployment permissions are restricted to one bucket and distribution.
