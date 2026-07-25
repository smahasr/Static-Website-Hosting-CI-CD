# GitHub OIDC IAM Role

This document defines the AWS IAM identity and permissions used by GitHub
Actions to deploy the static application. GitHub exchanges an OIDC ID token
for temporary AWS STS credentials; no permanent AWS access key is stored in
Actions.

## Current resources

| Resource | Value |
|---|---|
| AWS account | `278261170910` |
| GitHub repository | `hemanth-kumar/REPLACE_WITH_REPO` |
| Protected deployment branch | `main` |
| OIDC provider | `arn:aws:iam::278261170910:oidc-provider/token.actions.githubusercontent.com` |
| OIDC audience | `sts.amazonaws.com` |
| IAM role | `GitHubBmwX6ProductionDeployRole` |
| S3 bucket | `bmw-x6-static-prod-app-278261170910` |
| CloudFront distribution | `EXVN0DAFZ24IG` |

These values are identifiers, not secrets.

## Create the GitHub Actions OIDC provider

In **AWS IAM → Identity providers → Add provider**, use:

```text
Provider type: OpenID Connect
Provider URL: https://token.actions.githubusercontent.com
Audience: sts.amazonaws.com
```

Only one `token.actions.githubusercontent.com` provider is required per AWS
account. Reuse an existing provider when its audience already contains
`sts.amazonaws.com`.

## Reusable role trust policy

Replace the placeholders with the exact AWS account and GitHub repository
values:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<AWS_ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:<GITHUB_OWNER>/<GITHUB_REPO>:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

This policy allows only the named GitHub repository's `main` branch to assume
the role. The repository path is exact and case-sensitive.

## Trust policy used by this project

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::278261170910:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
          "token.actions.githubusercontent.com:sub": "repo:hemanth-kumar/REPLACE_WITH_REPO:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

## Reusable least-privilege permissions policy

Replace all placeholders before attaching the inline policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListDeploymentBucket",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::<S3_BUCKET>"
    },
    {
      "Sid": "ManageDeploymentObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::<S3_BUCKET>/*"
    },
    {
      "Sid": "InvalidateDistribution",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateInvalidation",
        "cloudfront:GetInvalidation"
      ],
      "Resource": "arn:aws:cloudfront::<AWS_ACCOUNT_ID>:distribution/<CLOUDFRONT_DISTRIBUTION_ID>"
    }
  ]
}
```

## Permissions policy used by this project

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListDeploymentBucket",
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::bmw-x6-static-prod-app-278261170910"
    },
    {
      "Sid": "ManageDeploymentObjects",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::bmw-x6-static-prod-app-278261170910/*"
    },
    {
      "Sid": "InvalidateDistribution",
      "Effect": "Allow",
      "Action": [
        "cloudfront:CreateInvalidation",
        "cloudfront:GetInvalidation"
      ],
      "Resource": "arn:aws:cloudfront::278261170910:distribution/EXVN0DAFZ24IG"
    }
  ]
}
```

Name the inline policy:

```text
BmwX6StaticDeploymentPolicy
```

Do not attach `AdministratorAccess`, `PowerUserAccess`, or
`AmazonS3FullAccess`.

## GitHub Actions variables

Configure these as GitHub Actions repository variables (**Settings → Secrets
and variables → Actions → Variables**):

```text
AWS_REGION=us-east-1
AWS_ROLE_ARN=arn:aws:iam::<AWS_ACCOUNT_ID>:role/<ROLE_NAME>
S3_BUCKET=<S3_BUCKET>
CLOUDFRONT_DISTRIBUTION_ID=<DISTRIBUTION_ID>
SITE_URL=https://<CLOUDFRONT_DOMAIN>
```

Do not create GitHub Actions secrets named `AWS_ACCESS_KEY_ID` or
`AWS_SECRET_ACCESS_KEY`.

## GitHub Actions workflow OIDC configuration

The deployment job requests an ID token by declaring these permissions, with
the same audience configured in IAM:

```yaml
permissions:
  id-token: write
  contents: read
```

It exchanges the token for temporary credentials using the official action:

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: ${{ vars.AWS_ROLE_ARN }}
    aws-region: ${{ vars.AWS_REGION }}
    role-session-name: GitHubActions-${{ github.run_id }}

- run: aws sts get-caller-identity
```

The resulting credentials expire after one hour and exist only inside the job.

## Apply through the AWS Console

1. Open **IAM → Roles → Create role**.
2. Select **Web identity**.
3. Select the `token.actions.githubusercontent.com` provider.
4. Select the `sts.amazonaws.com` audience.
5. Create the role.
6. Open **Trust relationships → Edit trust policy**.
7. Paste the completed trust policy.
8. Open **Permissions → Add permissions → Create inline policy**.
9. Paste the completed least-privilege permissions policy.
10. Confirm no broad AWS-managed policies are attached.

## Verification

Inspect the trust relationship:

```bash
aws iam get-role \
  --role-name "<ROLE_NAME>" \
  --query Role.AssumeRolePolicyDocument
```

List inline policies:

```bash
aws iam list-role-policies \
  --role-name "<ROLE_NAME>"
```

Confirm no broad managed policies are attached:

```bash
aws iam list-attached-role-policies \
  --role-name "<ROLE_NAME>"
```

Expected result:

```json
{
  "AttachedPolicies": []
}
```

The strongest end-to-end verification is a successful protected `main`
workflow run whose deploy job log shows:

```text
aws sts get-caller-identity
aws s3 sync
aws cloudfront create-invalidation
```

## Troubleshooting

| Error | Likely cause |
|---|---|
| `InvalidIdentityToken` | OIDC provider URL or audience does not match the GitHub token |
| `AccessDenied` from STS | The trust policy repository path or branch is incorrect |
| Environment variables are empty | The job is not running on the protected `main` branch or the `production` environment |
| S3 `AccessDenied` | Bucket name or object ARN is incorrect in the permissions policy |
| CloudFront invalidation denied | Distribution ID or distribution ARN is incorrect |
| Another branch can deploy | The trust policy `sub` condition is too broad |

## Security rules

- Keep the OIDC audience equal to `sts.amazonaws.com` in AWS and GitHub Actions.
- Restrict `token.actions.githubusercontent.com:sub` to one repository and the
  protected production branch.
- Use temporary STS credentials only.
- Do not store permanent IAM user keys in GitHub.
- Do not attach broad AWS-managed policies to the deployment role.
- Rotate and delete any recovery credentials used outside the pipeline.
- Keep the S3 origin private according to [s3-policy.md](s3-policy.md).
