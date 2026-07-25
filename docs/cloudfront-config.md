# CloudFront Configuration

This document defines the Amazon CloudFront configuration used to deliver the
static application securely from its private Amazon S3 origin.

## Current resources

| Resource | Value |
|---|---|
| AWS account | `278261170910` |
| AWS region | `us-east-1` |
| S3 origin bucket | `bmw-x6-static-prod-app-278261170910` |
| Distribution ID | `EXVN0DAFZ24IG` |
| Distribution domain | `d3tt9aj7gt60mn.cloudfront.net` |
| Production URL | `https://d3tt9aj7gt60mn.cloudfront.net` |
| Origin Access Control | `E59PJ90H2BRPQ` |
| Managed cache policy | `CachingOptimized` |
| Managed response headers policy | `SecurityHeadersPolicy` |
| Response headers policy ID | `67f7725c-6f97-4210-82d7-5512b31e9d03` |

These values are resource identifiers and are not credentials.

## Architecture

```text
Browser
   |
   | HTTPS
   v
Amazon CloudFront
   |
   | Signed SigV4 request through OAC
   v
Private Amazon S3 bucket
```

CloudFront is the only public endpoint. The S3 website endpoint is not used,
and direct S3 object access is blocked.

## Required distribution settings

Configure the distribution with:

| Setting | Required value |
|---|---|
| Distribution type | Standard distribution |
| Origin type | Amazon S3 |
| Origin domain | Regular S3 bucket endpoint |
| Origin access | Origin Access Control |
| OAC signing behavior | Always sign |
| OAC signing protocol | SigV4 |
| Default root object | `index.html` |
| Viewer protocol policy | Redirect HTTP to HTTPS |
| Allowed methods | `GET`, `HEAD` |
| Cached methods | `GET`, `HEAD` |
| Compression | Enabled |
| Cache policy | Managed `CachingOptimized` |
| Response headers policy | Managed `SecurityHeadersPolicy` |
| Alternate domain | None for the initial deployment |
| Viewer certificate | Default CloudFront certificate |
| Distribution status | Enabled |

Do not configure the S3 static website endpoint as a custom origin. OAC works
with the regular S3 REST origin.

## Create the distribution in the AWS Console

1. Open **AWS Console → CloudFront → Distributions**.
2. Select **Create distribution**.
3. Choose **Single website or app**.
4. For origin type, select **Amazon S3**.
5. Select the private deployment bucket.
6. Under origin access, select **Origin access control settings**.
7. Create or select an OAC with:
   - Origin type: S3
   - Signing behavior: Sign requests
   - Signing protocol: SigV4
8. Allow CloudFront to update the S3 bucket policy.
9. Set viewer protocol policy to **Redirect HTTP to HTTPS**.
10. Allow `GET` and `HEAD`.
11. Enable automatic compression.
12. Select the managed `CachingOptimized` cache policy.
13. Attach the managed `SecurityHeadersPolicy` response headers policy.
14. Use the default CloudFront certificate.
15. Create the distribution.
16. Open the created distribution and set **Default root object** to
    `index.html`.
17. Wait until the status changes from `Deploying` to `Deployed`.

The required S3 bucket policy is documented in [s3-policy.md](s3-policy.md).

## Origin Access Control

The OAC must sign all requests:

```text
Origin type: S3
Signing behavior: Always
Signing protocol: SigV4
```

The corresponding bucket policy allows `cloudfront.amazonaws.com` to call
`s3:GetObject` only when `AWS:SourceArn` matches this distribution.

This provides:

- A private S3 origin
- HTTPS between CloudFront and S3
- Distribution-specific origin access
- No public S3 ACLs or bucket policies

## Default cache behavior

The default behavior should use:

```text
Path pattern: Default (*)
Viewer protocol policy: Redirect HTTP to HTTPS
Allowed methods: GET, HEAD
Cached methods: GET, HEAD
Compress objects automatically: Yes
Cache policy: CachingOptimized
Response headers policy: SecurityHeadersPolicy
```

The deployment pipeline controls object metadata:

```text
index.html:
  Cache-Control: no-cache,no-store,must-revalidate

CSS, JavaScript, and image assets:
  Cache-Control: public,max-age=86400
```

HTML is revalidated on each request, while static assets can remain cached for
one day. The pipeline creates a `/*` invalidation after every production
deployment.

## Default root object

Set:

```text
Default root object: index.html
```

Without this setting, requesting `/` can return `403` even when `index.html`
exists and CloudFront can read it.

This application has no client-side history routing. Custom `403` or `404`
responses that rewrite to `index.html` are therefore unnecessary.

## Security headers

Attach the AWS-managed `SecurityHeadersPolicy`.

Expected response headers include:

```text
Strict-Transport-Security
X-Content-Type-Options
X-Frame-Options
X-XSS-Protection
Referrer-Policy
```

For this project, the managed response headers policy ID is:

```text
67f7725c-6f97-4210-82d7-5512b31e9d03
```

Use the policy name rather than hard-coding the ID when configuring another AWS
partition or when retrieving it programmatically.

## Deployment invalidation

The GitHub Actions deployment job invalidates the distribution after uploading:

```bash
INVALIDATION_ID=$(aws cloudfront create-invalidation \
  --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
  --paths "/*" \
  --query 'Invalidation.Id' \
  --output text)

aws cloudfront wait invalidation-completed \
  --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
  --id "$INVALIDATION_ID"
```

The deployment role requires:

```text
cloudfront:CreateInvalidation
cloudfront:GetInvalidation
```

These permissions must be restricted to the intended distribution ARN. See
[iam-role.md](iam-role.md).

## GitHub Actions variables

The pipeline requires:

```text
CLOUDFRONT_DISTRIBUTION_ID=EXVN0DAFZ24IG
SITE_URL=https://d3tt9aj7gt60mn.cloudfront.net
```

For another deployment, replace both values with the new distribution's ID and
full HTTPS domain.

## Useful AWS CLI commands

Get the distribution:

```bash
aws cloudfront get-distribution \
  --id "<DISTRIBUTION_ID>"
```

Get its editable configuration and ETag:

```bash
aws cloudfront get-distribution-config \
  --id "<DISTRIBUTION_ID>"
```

Wait for a configuration update:

```bash
aws cloudfront wait distribution-deployed \
  --id "<DISTRIBUTION_ID>"
```

List managed cache policies:

```bash
aws cloudfront list-cache-policies \
  --type managed
```

List managed response headers policies:

```bash
aws cloudfront list-response-headers-policies \
  --type managed
```

Create a manual invalidation:

```bash
aws cloudfront create-invalidation \
  --distribution-id "<DISTRIBUTION_ID>" \
  --paths "/*"
```

## Updating the distribution with the AWS CLI

CloudFront updates require the complete distribution configuration and its
current ETag:

```bash
aws cloudfront get-distribution-config \
  --id "<DISTRIBUTION_ID>" \
  > distribution-config-response.json
```

1. Record the returned `ETag`.
2. Extract and edit only the `DistributionConfig` object.
3. Preserve all existing required fields.
4. Submit the complete configuration:

```bash
aws cloudfront update-distribution \
  --id "<DISTRIBUTION_ID>" \
  --if-match "<ETAG>" \
  --distribution-config file://distribution-config.json
```

5. Wait for the distribution to become deployed.

Do not submit only the field being changed; the update API expects the complete
configuration.

## Verification

Verify the root page:

```bash
curl -I "https://<CLOUDFRONT_DOMAIN>/"
```

Expected result:

```text
HTTP/2 200
content-type: text/html
cache-control: no-cache,no-store,must-revalidate
```

Verify a static asset:

```bash
curl -I \
  "https://<CLOUDFRONT_DOMAIN>/assets/bmw-x6-hero.png"
```

Expected result: `200`.

Verify HTTP redirects to HTTPS:

```bash
curl -I "http://<CLOUDFRONT_DOMAIN>/"
```

Expected result: an HTTP redirect to the HTTPS URL.

Verify security headers:

```bash
curl -sI "https://<CLOUDFRONT_DOMAIN>/" | \
  grep -Ei \
  'strict-transport-security|x-content-type-options|x-frame-options|referrer-policy'
```

Verify direct S3 access is blocked:

```bash
curl -o /dev/null -s -w '%{http_code}\n' \
  "https://<S3_BUCKET>.s3.<AWS_REGION>.amazonaws.com/index.html"
```

Expected result: `403`.

## Troubleshooting

| Symptom | Likely cause or action |
|---|---|
| `/` returns `403` | Set the default root object to `index.html` |
| All objects return `403` | Check the OAC attachment and S3 bucket policy distribution ARN |
| Direct S3 URL returns `200` | The bucket is public; enable all public access blocks |
| Browser shows old content | Create a `/*` invalidation and wait for completion |
| Invalidation is denied | Correct the IAM role's distribution ARN and permissions |
| HTTP does not redirect | Set viewer protocol policy to Redirect HTTP to HTTPS |
| Security headers are missing | Attach the managed `SecurityHeadersPolicy` |
| CSS or images fail | Confirm the files exist in S3 with the same case-sensitive paths |
| Distribution update fails with ETag error | Retrieve the latest configuration and ETag, then retry |
| `SITE_URL` verification fails | Confirm the GitHub Actions variable contains the full HTTPS URL |

## Security and operational rules

- Keep the S3 origin private.
- Always use OAC with signed requests.
- Redirect viewers from HTTP to HTTPS.
- Keep security headers enabled.
- Restrict invalidation permissions to one distribution.
- Never put access keys, secret keys, or session tokens in this document.
- Wait for configuration deployment and invalidation completion before
  verifying a release.
- Use Git-based redeployment as the preferred rollback mechanism.

