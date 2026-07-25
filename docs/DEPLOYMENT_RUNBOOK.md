# GitHub to AWS Static Site Deployment Runbook

This runbook records the complete setup, deployment, troubleshooting, and
verification process used for this project. It is written so the same
architecture can be recreated for another static application.

## 1. Architecture

```text
Developer
   |
   | git push
   v
GitHub repository
   |
   | GitHub Actions workflow
   v
Validate -> Package -> Manual production approval
   |
   | GitHub OIDC / temporary AWS credentials
   v
Private Amazon S3 bucket
   |
   | CloudFront Origin Access Control
   v
Amazon CloudFront HTTPS endpoint
   |
   v
Browser
```

The S3 bucket is a private object origin, not a public S3 website. CloudFront
is the only public entry point. GitHub Actions uses OpenID Connect (OIDC) to
assume an AWS role, so the pipeline does not store permanent AWS access keys.

## 2. Current production inventory

These identifiers describe the deployment created for this project. Use new
values when repeating the setup in another account or repository.

| Resource | Current value |
|---|---|
| GitHub repository | `hemanth-kumar/REPLACE_WITH_REPO` |
| Default/protected branch | `main` |
| AWS account | `278261170910` |
| AWS region | `us-east-1` |
| S3 bucket | `bmw-x6-static-prod-app-278261170910` |
| CloudFront distribution | `EXVN0DAFZ24IG` |
| CloudFront URL | `https://d3tt9aj7gt60mn.cloudfront.net` |
| CloudFront OAC | `E59PJ90H2BRPQ` |
| IAM role | `GitHubBmwX6ProductionDeployRole` |
| GitHub OIDC audience | `sts.amazonaws.com` |

Do not place access keys, secret keys, GitHub tokens, or ID tokens in this
document, the repository, commits, workflow logs, or GitHub Actions
variables.

## 3. Prerequisites

Before recreating the deployment, have:

- An AWS account with permission to manage S3, CloudFront, IAM, and OIDC
  providers.
- A GitHub repository and permission to configure branch protection,
  environments, Actions variables, and workflows.
- Git installed locally.
- The static site entry point and its local assets committed to the repository.
- Multi-factor authentication enabled for administrative accounts.

Choose and record these values:

```text
AWS_ACCOUNT_ID=<12-digit-account-id>
AWS_REGION=us-east-1
GITHUB_REPOSITORY=<owner>/<repository>
S3_BUCKET=<globally-unique-bucket-name>
CLOUDFRONT_DISTRIBUTION_ID=<created-later>
SITE_URL=<created-later>
```

## 4. Prepare GitHub

1. Create a blank GitHub repository.
2. Do not initialize it with sample files if a local repository already exists.
3. Push the static application to the repository root.
4. Make `main` the default branch.
5. Open **Settings -> Branches -> Branch protection rules**.
6. Protect `main` and restrict production changes to the intended maintainers.
7. Open **Settings -> Environments** and create a `production` environment
   with required reviewers, so the `deploy` job pauses for manual approval.
8. Record the exact `owner/repository` path shown by GitHub. OIDC matching is
   exact and case-sensitive.

For this repository, `index.html`, `styles.css`, `script.js`, and `assets/`
are at the Git repository root. Workflow paths must be relative to that root.

## 5. Create and secure the S3 origin

In **AWS Console -> S3 -> Create bucket**:

1. Create a globally unique bucket in `us-east-1`.
2. Keep Object Ownership set to **Bucket owner enforced**.
3. Enable all four S3 Block Public Access controls:
   - Block public ACLs.
   - Ignore public ACLs.
   - Block public bucket policies.
   - Restrict public buckets.
4. Enable bucket versioning.
5. Use SSE-S3 default encryption unless the application requires a customer
   managed KMS key.
6. Leave **Static website hosting disabled**.
7. Do not add a public-read ACL or public bucket policy.

Versioning provides an emergency object-level recovery option. Normal rollback
should still redeploy a known-good Git commit.

## 6. Create CloudFront

In **AWS Console -> CloudFront -> Create distribution**:

1. Select the regular S3 bucket as the origin. Do not select or enter an S3
   website endpoint.
2. Create an Origin Access Control:
   - Origin type: S3.
   - Signing behavior: always sign requests.
   - Signing protocol: SigV4.
3. Allow CloudFront to update the bucket policy, or install the equivalent
   restricted policy manually.
4. Set the default root object to `index.html`.
5. Set viewer protocol policy to **Redirect HTTP to HTTPS**.
6. Enable compression.
7. Use the managed `CachingOptimized` cache policy.
8. Attach the managed `SecurityHeadersPolicy` response headers policy.
9. Use the default CloudFront certificate when no custom domain is required.
10. Wait until the distribution status becomes **Deployed**.

The S3 bucket policy must allow `s3:GetObject` to the CloudFront service
principal only when the source is the intended distribution:

```json
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::<S3_BUCKET>/*",
      "Condition": {
        "ArnLike": {
          "AWS:SourceArn": "arn:aws:cloudfront::<AWS_ACCOUNT_ID>:distribution/<DISTRIBUTION_ID>"
        }
      }
    }
  ]
}
```

Record the distribution ID and `https://...cloudfront.net` domain.

## 7. Configure GitHub OIDC in AWS

In **AWS Console -> IAM -> Identity providers -> Add provider**:

```text
Provider type: OpenID Connect
Provider URL: https://token.actions.githubusercontent.com
Audience: sts.amazonaws.com
```

Create an IAM role for web identity and use this trust policy:

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
          "token.actions.githubusercontent.com:sub": "repo:<OWNER>/<REPOSITORY>:ref:refs/heads/main"
        }
      }
    }
  ]
}
```

The `sub` value must use the real GitHub `owner/repository` path. A different
owner, repository name, or branch causes `AssumeRoleWithWebIdentity` to fail.

Attach one least-privilege inline policy:

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
      "Resource": "arn:aws:cloudfront::<AWS_ACCOUNT_ID>:distribution/<DISTRIBUTION_ID>"
    }
  ]
}
```

Do not attach `AdministratorAccess` or `AmazonS3FullAccess`. The inline policy
is sufficient for this pipeline.

## 8. Configure GitHub Actions secrets and variables

Open **GitHub -> Settings -> Secrets and variables -> Actions -> Variables**
and add:

| Variable | Value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `AWS_ROLE_ARN` | Deployment role ARN |
| `S3_BUCKET` | Private origin bucket |
| `CLOUDFRONT_DISTRIBUTION_ID` | Distribution ID |
| `SITE_URL` | Full `https://...cloudfront.net` URL |

These are resource identifiers rather than credentials, so repository
variables (not secrets) are appropriate. Restrict who can approve the
`production` environment instead, so deployment still requires manual review.

Do not define `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` in GitHub. The
deploy job obtains temporary credentials through OIDC.

## 9. Pipeline behavior

The committed `.github/workflows/deploy.yml` is the authoritative pipeline
definition. It has four jobs.

### Validate

- Confirms required source files exist.
- Parses JavaScript with `node --check`.
- Validates `index.html` with `html-validate`.
- Runs for pushes to any branch and for pull requests.

Before pushing a workflow change, validate locally:

```bash
node --check script.js
npx --yes html-validate index.html
```

Also open the **Actions** tab after pushing and confirm the workflow parses
and starts. A syntactically valid YAML file can still fail later if its
paths, action versions, or commands are wrong.

### Package

- Copies only deployable files into `dist/`.
- Does not upload the source reference image, README, Git metadata, or tokens.
- Uploads `dist/` as a workflow artifact for 30 days with
  `actions/upload-artifact@v4`.

### Deploy

- Exists only on `main` (`if: github.ref == 'refs/heads/main'`).
- Targets the `production` environment, which requires manual approval from a
  designated reviewer before the job runs.
- Declares `permissions: id-token: write` and requests a GitHub Actions ID
  token with audience `sts.amazonaws.com` through
  `aws-actions/configure-aws-credentials@v4`.
- Exchanges the token for one-hour AWS STS credentials.
- Synchronizes non-HTML assets with a one-day cache duration.
- Uploads `index.html` with a no-cache policy.
- Removes obsolete deployed assets with `aws s3 sync --delete`.
- Creates and waits for a full CloudFront invalidation.

The job runs on `ubuntu-latest` with the AWS CLI preinstalled. When pinning a
specific AWS CLI or action version, confirm the exact tag exists before
committing it.

### Verify

- Requests the CloudFront home page.
- Confirms the expected HTML title is present.
- Confirms the hero asset is publicly accessible through CloudFront.

## 10. First deployment and normal releases

Push the initial repository:

```bash
git init -b main
git remote add origin https://github.com/<OWNER>/<REPOSITORY>.git
git add .
git commit -m "Configure static site deployment"
git push -u origin main
```

For each release:

1. Create a feature branch.
2. Make and locally test the change.
3. Push the branch and open a pull request.
4. Confirm validation and packaging succeed.
5. Merge into protected `main`.
6. Open the resulting workflow run under the **Actions** tab.
7. Approve the `production` environment when the `deploy` job requests review.
8. Wait for `verify` to succeed.
9. Open the production environment URL and perform a browser smoke test.

## 11. End-to-end verification

After deployment, verify:

```bash
curl -I https://<CLOUDFRONT_DOMAIN>
curl -I https://<CLOUDFRONT_DOMAIN>/assets/bmw-x6-hero.png
curl -o /dev/null -s -w '%{http_code}\n' \
  https://<S3_BUCKET>.s3.us-east-1.amazonaws.com/index.html
```

Expected results:

- CloudFront home page: `200`.
- CloudFront asset: `200`.
- Direct S3 object request: `403`.
- HTTP viewer requests redirect to HTTPS.
- The HTML response uses `no-cache,no-store,must-revalidate`.
- Security headers include HSTS, `X-Content-Type-Options`, frame protection,
  and a referrer policy.
- The S3 bucket contains only the intended deployment files.
- All four S3 public access block controls are `true`.
- The deployment role has no broad AWS-managed S3 policy.

## 12. Problems to watch for when migrating from GitLab CI/CD

### Workflow YAML structure

Cause: GitHub Actions jobs must sit directly under the top-level `jobs:` key,
each with its own `runs-on` and `steps:` list — unlike GitLab CI, there is no
shared top-level `stages:` list that jobs attach to via a `stage:` key.

Fix: define `validate`, `package`, `deploy`, and `verify` as sibling entries
under `jobs:`, and use `needs:` to express the same validate → package →
deploy → verify ordering GitLab expressed through `stages:`.

### Workflow paths must match the repository

Cause: commands referencing a subdirectory name will fail if the workflow
already runs from the repository root.

Fix: use repository-root paths such as `index.html`, `script.js`, and
`assets/bmw-x6-hero.png`, and always add an `actions/checkout@v4` step first
so the workspace actually contains those files.

### HTML upload command must stay on one line

Cause: splitting a multi-flag `aws` CLI command across multiple YAML lines
without a line continuation produces a malformed command.

Fix: keep the complete `aws s3 cp` command and its `--cache-control` value in
one `run:` step (or use YAML's `|` block scalar consistently).

### Validation passed YAML but failed HTML

Cause: the document had a lowercase doctype and accessibility errors involving
ARIA labels and focusable controls inside a hidden chat panel.

Fix:

- Changed the declaration to `<!DOCTYPE html>`.
- Marked the visual M badge with an image role.
- Made the hidden chat panel inert and synchronized that state in JavaScript.

### OIDC role assumption would have failed

Cause: the IAM trust policy named a different GitHub repository than the one
actually running the workflow.

Fix: use the actual subject, matching the workflow's repository and branch
exactly:

```text
repo:hemanth-kumar/REPLACE_WITH_REPO:ref:refs/heads/main
```

### Production URL was incorrect

Cause: the `SITE_URL` variable did not match the created distribution.

Fix: update it to the full assigned CloudFront HTTPS URL.

### CloudFront root URL was not configured

Cause: the distribution had no default root object.

Fix: set `DefaultRootObject` to `index.html`.

### S3 was configured as a public website

Cause: S3 static website hosting was enabled and all public access blocks were
disabled.

Fix:

- Disable S3 static website hosting.
- Enable all four public access blocks.
- Retain only the OAC-restricted CloudFront read policy.

### Deployment role had excessive permissions

Cause: `AmazonS3FullAccess` was attached in addition to the restricted inline
policy.

Fix: detach `AmazonS3FullAccess` and keep only the bucket- and
distribution-specific inline policy.

## 13. Troubleshooting sequence

Use this order because it follows the request path:

1. Open the **Actions** tab. If the workflow shows no jobs, fix the YAML
   structure first.
2. Inspect the failed job's step logs, not only the run status.
3. Confirm every workflow path is relative to the Git repository root.
4. Confirm the runner image and any pinned action versions are valid.
5. Confirm repository variables are configured and the `production`
   environment is approved.
6. Compare the OIDC `sub` claim with the exact `owner/repository` path.
7. Use `aws sts get-caller-identity` inside the job to confirm role assumption.
8. Check the role's inline permissions against the exact bucket and
   distribution ARNs.
9. Confirm files reached S3.
10. Confirm CloudFront has `index.html` as its default root.
11. Wait for invalidation completion.
12. Test CloudFront and direct S3 access independently.

Common symptoms:

| Symptom | Likely cause |
|---|---|
| Workflow run shows no jobs | Invalid `.github/workflows/deploy.yml` structure |
| `test -f` or `cp` fails | Repository-relative path is wrong |
| Job fails before any step runs | Runner image or pinned action version cannot be resolved |
| `InvalidIdentityToken` | OIDC provider or audience mismatch |
| `AccessDenied` from STS | Trust policy `sub` does not match repository/branch |
| `AccessDenied` from S3 | Role policy uses the wrong bucket ARN |
| CloudFront `/` returns 403 | No default root object or missing S3 object |
| CloudFront serves old files | Cache invalidation missing or incomplete |
| Direct S3 URL returns 200 | Bucket is public and must be secured |

## 14. Rollback

Preferred rollback:

1. Identify the last known-good Git commit.
2. Revert the faulty commit or redeploy the earlier workflow artifact.
3. Re-run the `deploy` job and approve the `production` environment.
4. Wait for CloudFront invalidation and verification.

Example:

```bash
git revert <BAD_COMMIT_SHA>
git push origin main
```

Use S3 version restoration only when a normal Git-based redeployment is not
possible.

## 15. Credential handling and cleanup

Local `.aws-token` and `.gh-token` files should only ever be used for
recovery and inspection. They belong outside this Git repository and are not
needed by the working pipeline.

After recovery:

1. Revoke or rotate the GitHub personal access token.
2. Deactivate and delete the exposed IAM access key.
3. Remove plaintext credential files from the workstation.
4. Confirm the pipeline still deploys through OIDC.
5. Review CloudTrail and GitHub audit log activity if a credential was
   exposed in terminal output, chat, logs, or screen sharing.

Never commit credential files. OIDC is the permanent authentication mechanism
for this deployment.

## 16. Current successful outcome

The final workflow run completed:

```text
validate   success
package    success
deploy     success
verify     success
```

Production verification confirmed:

- CloudFront status: deployed.
- HTTPS home page: `200`.
- Expected page title present.
- Expected four deployment objects in S3.
- Direct S3 access: `403`.
- All S3 public access blocks enabled.
- CloudFront managed security headers active.
- No broad AWS-managed policies attached to the deployment role.
