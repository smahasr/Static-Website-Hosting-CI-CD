# S3 and CloudFront Origin Policy

This document defines the secure Amazon S3 origin configuration used by this
project. The bucket is private and can be read publicly only through the
approved Amazon CloudFront distribution.

## Current resources

| Resource | Value |
|---|---|
| AWS account | `278261170910` |
| AWS region | `us-east-1` |
| S3 bucket | `bmw-x6-static-prod-app-278261170910` |
| CloudFront distribution | `EXVN0DAFZ24IG` |
| CloudFront OAC | `E59PJ90H2BRPQ` |

These identifiers are not credentials. Never add access keys, secret keys, or
session tokens to this file.

## Required bucket configuration

Configure the bucket with:

- Object Ownership: `BucketOwnerEnforced`
- Versioning: enabled
- Default encryption: SSE-S3 (`AES256`)
- Static website hosting: disabled
- ACLs: disabled
- Block Public Access: all four settings enabled

The required Block Public Access configuration is:

```json
{
  "BlockPublicAcls": true,
  "IgnorePublicAcls": true,
  "BlockPublicPolicy": true,
  "RestrictPublicBuckets": true
}
```

Do not make the bucket public. CloudFront uses Origin Access Control and signed
SigV4 requests to retrieve objects.

## Reusable CloudFront bucket policy

Replace the placeholders before applying this policy:

```json
{
  "Version": "2008-10-17",
  "Id": "PolicyForCloudFrontPrivateContent",
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
          "AWS:SourceArn": "arn:aws:cloudfront::<AWS_ACCOUNT_ID>:distribution/<CLOUDFRONT_DISTRIBUTION_ID>"
        }
      }
    }
  ]
}
```

## Policy used by this project

```json
{
  "Version": "2008-10-17",
  "Id": "PolicyForCloudFrontPrivateContent",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::bmw-x6-static-prod-app-278261170910/*",
      "Condition": {
        "ArnLike": {
          "AWS:SourceArn": "arn:aws:cloudfront::278261170910:distribution/EXVN0DAFZ24IG"
        }
      }
    }
  ]
}
```

The condition prevents another CloudFront distribution from using this
permission.

## Apply through the AWS Console

1. Open **S3 → Buckets**.
2. Select the deployment bucket.
3. Open **Permissions → Bucket policy**.
4. Paste the completed policy.
5. Confirm the bucket name, account ID, and distribution ID are correct.
6. Save the policy.
7. Under **Block public access**, confirm all four settings are enabled.
8. Under **Properties**, confirm static website hosting is disabled.

CloudFront should be configured with:

- The regular S3 bucket endpoint as its origin
- Origin Access Control enabled
- Signing behavior set to always sign
- Default root object set to `index.html`
- Viewer protocol policy set to redirect HTTP to HTTPS

## Apply with the AWS CLI

Store the reusable policy in a local JSON file after replacing its placeholders:

```bash
aws s3api put-bucket-policy \
  --bucket "<S3_BUCKET>" \
  --policy file://bucket-policy.json

aws s3api put-public-access-block \
  --bucket "<S3_BUCKET>" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api delete-bucket-website \
  --bucket "<S3_BUCKET>"
```

## Verification

Check the bucket policy:

```bash
aws s3api get-bucket-policy \
  --bucket "<S3_BUCKET>" \
  --query Policy \
  --output text
```

Check public access controls:

```bash
aws s3api get-public-access-block \
  --bucket "<S3_BUCKET>"
```

Check versioning:

```bash
aws s3api get-bucket-versioning \
  --bucket "<S3_BUCKET>"
```

Confirm CloudFront access succeeds:

```bash
curl -I "https://<CLOUDFRONT_DOMAIN>/"
```

Expected result: `200`.

Confirm direct S3 access is blocked:

```bash
curl -o /dev/null -s -w '%{http_code}\n' \
  "https://<S3_BUCKET>.s3.<AWS_REGION>.amazonaws.com/index.html"
```

Expected result: `403`.

## Troubleshooting

| Symptom | Check |
|---|---|
| CloudFront returns `403` | Confirm `index.html` exists and the distribution has the correct default root object |
| CloudFront cannot read objects | Confirm the OAC is attached and the policy contains the correct distribution ARN |
| Direct S3 access returns `200` | Re-enable all public access blocks and remove public policies or ACLs |
| Policy cannot be saved | Confirm public access blocking is not rejecting an accidentally public statement |
| Old content is displayed | Create a CloudFront invalidation for `/*` |

## Security rules

- Never use `"Principal": "*"` for this origin bucket.
- Never grant public `s3:GetObject`.
- Never use the S3 website endpoint with this private OAC architecture.
- Never place AWS credentials in S3 policies or repository files.
- Keep the distribution-specific `AWS:SourceArn` condition.
- Use GitHub OIDC and the deployment role described in [iam-role.md](iam-role.md)
  for uploads.

