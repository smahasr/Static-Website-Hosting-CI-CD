# Start Here — Full Manual Setup Guide (AWS Console, GitHub Actions)

Everything needed to stand this project up from zero, by hand: repo, AWS
resources via the console (no Terraform), IAM OIDC role, branching model,
pipeline stages, secrets, triggers, build, deploy, email alerts, rollback,
CloudFront invalidation, and the 403/404 → `index.html` fix.

Placeholders to replace throughout: `<OWNER>`, `<REPO>`, `<AWS_ACCOUNT_ID>`,
`<S3_BUCKET>`, `<DISTRIBUTION_ID>`, `<CLOUDFRONT_DOMAIN>`.

---

## 1. Create the GitHub repository

1. github.com → **New repository**.
2. Name it (e.g. `<REPO>`), visibility your choice, no README/gitignore if
   pushing an existing local folder.
3. Create.

## 2. Clone, push initial code

```bash
git clone https://github.com/<OWNER>/<REPO>.git
cd <REPO>
# copy this project's files in (website/, docs/, terraform/, .github/, README.md, Start.md)
git add .
git commit -m "Initial commit"
git branch -M main
git push -u origin main
```

## 3. Branch protection on `main`

1. Repo → **Settings → Branches → Add branch protection rule**.
2. Branch pattern: `main`.
3. Enable: require a pull request before merging, require status checks to
   pass (`validate`, `package` once the workflow has run once), do not allow
   force pushes, do not allow deletions.
4. Save.

## 4. Branch → PR → merge workflow (day-to-day)

```bash
git checkout main
git pull
git checkout -b feature/update-site

# edit files
git add .
git commit -m "Update static website"
git push -u origin feature/update-site
```

Open a **Pull Request** on GitHub targeting `main`. Wait for `validate` and
`package` checks to go green. Merge (squash or merge commit, your call).
Merging into `main` is what triggers the `deploy` job later in this guide.

---

## 5. Create the S3 origin bucket (console)

1. AWS Console → **S3 → Create bucket**.
2. Bucket name: `<S3_BUCKET>` (globally unique), region `us-east-1` (or your
   choice — keep it consistent everywhere below).
3. Object Ownership: **ACLs disabled (Bucket owner enforced)**.
4. Block Public Access: leave **all four boxes checked** (block everything).
5. Bucket Versioning: **Enable**.
6. Default encryption: **SSE-S3 (Amazon S3 managed keys)**, bucket key: enable.
7. Create bucket.
8. Bucket → **Properties** → confirm **Static website hosting** is
   **Disabled**. This bucket is a private CloudFront origin, not a public
   website endpoint.

## 6. Create the CloudFront distribution + Origin Access Control (console)

1. AWS Console → **CloudFront → Create distribution**.
2. Origin domain: select the S3 bucket from step 5 (pick the **regular**
   bucket endpoint, not the S3 website endpoint).
3. Origin access: **Origin access control settings (recommended)** → **Create
   control setting**:
   - Signing behavior: **Sign requests (recommended)**
   - Signing protocol: **SigV4**
4. Viewer protocol policy: **Redirect HTTP to HTTPS**.
5. Allowed HTTP methods: **GET, HEAD**.
6. Cache policy: **CachingOptimized** (managed).
7. Response headers policy: **SecurityHeadersPolicy** (managed).
8. Default root object: `index.html`.
9. Create distribution. Wait for status **Deployed** (several minutes).
10. CloudFront will offer to auto-update the S3 bucket policy for the new
    OAC — accept it, or apply the policy manually in step 7 below.
11. Note the **Distribution ID** and the **Distribution domain name**
    (`<CLOUDFRONT_DOMAIN>`, looks like `dxxxxxxxxxx.cloudfront.net`).

## 7. S3 bucket policy for CloudFront OAC (console)

If CloudFront didn't auto-apply it: S3 → bucket → **Permissions → Bucket
policy → Edit**:

```json
{
  "Version": "2008-10-17",
  "Id": "PolicyForCloudFrontPrivateContent",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": { "Service": "cloudfront.amazonaws.com" },
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

Save. This is the *only* way objects become readable — no public ACLs, no
public bucket policy statements, ever.

## 8. Fix 403/404 → serve `index.html`

Two separate things, both needed:

**a. Default root object (fixes `/` returning 403).**
Already set in step 6.9. If you skipped it: distribution → **General →
Edit** → Default root object: `index.html`.

**b. Custom error responses (fixes deep-link 403/404s falling through to a
CloudFront error page instead of your app).**
Distribution → **Error pages → Create custom error response**:

| HTTP error code | Response page path | HTTP response code | TTL |
|---|---|---|---|
| 403 | `/index.html` | 200 | 10 |
| 404 | `/index.html` | 200 | 10 |

This makes CloudFront serve `index.html` with a `200` for any path S3 can't
find directly (needed once you add client-side routes; skip it if the site
stays single-page with no router).

---

## 9. Create the GitHub OIDC identity provider in AWS (console)

1. AWS Console → **IAM → Identity providers → Add provider**.
2. Provider type: **OpenID Connect**.
3. Provider URL: `https://token.actions.githubusercontent.com` → **Get
   thumbprint**.
4. Audience: `sts.amazonaws.com`.
5. Add provider.

Skip this step if the account already has a
`token.actions.githubusercontent.com` provider — one per account is enough
for every repo.

## 10. Create the IAM deployment role (console)

1. IAM → **Roles → Create role**.
2. Trusted entity type: **Web identity**.
3. Identity provider: the one from step 9.
4. Audience: `sts.amazonaws.com`.
5. Next. Skip attaching managed policies for now — inline policy comes next.
6. Name it, e.g. `GitHub<Project>ProductionDeployRole`. Create role.
7. Open the role → **Trust relationships → Edit trust policy** → replace with:

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
          "token.actions.githubusercontent.com:sub": "repo:<OWNER>/<REPO>:environment:Production"
        }
      }
    }
  ]
}
```

Only the exact repo + `main` branch can assume this role. Nothing else.

8. **Permissions → Add permissions → Create inline policy** → JSON:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ListDeploymentBucket",
      "Effect": "Allow",
      "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
      "Resource": "arn:aws:s3:::<S3_BUCKET>"
    },
    {
      "Sid": "ManageDeploymentObjects",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
      "Resource": "arn:aws:s3:::<S3_BUCKET>/*"
    },
    {
      "Sid": "InvalidateDistribution",
      "Effect": "Allow",
      "Action": ["cloudfront:CreateInvalidation", "cloudfront:GetInvalidation"],
      "Resource": "arn:aws:cloudfront::<AWS_ACCOUNT_ID>:distribution/<DISTRIBUTION_ID>"
    }
  ]
}
```

Name it e.g. `StaticSiteDeploymentPolicy`, create. Never attach
`AdministratorAccess`, `PowerUserAccess`, or `AmazonS3FullAccess` here.

9. Copy the role's **ARN** (Role → Summary → ARN) — needed for
   `AWS_ROLE_ARN` below.

---

## 11. GitHub side: environment + manual approval

1. Repo → **Settings → Environments → New environment** → name it
   `production`.
2. **Required reviewers** → add yourself/your team. This is the manual
   approval gate — the `deploy` job pauses here until a reviewer clicks
   **Approve**.
3. (Optional) restrict which branches can deploy to this environment to
   `main` only, under **Deployment branches and tags**.
4. Save protection rules.

## 12. GitHub secrets and variables

**Settings → Secrets and variables → Actions**.

**Variables** tab (not secret — plain identifiers):

| Name | Value |
|---|---|
| `AWS_REGION` | `us-east-1` |
| `AWS_ROLE_ARN` | ARN from step 10.9 |
| `S3_BUCKET` | `<S3_BUCKET>` |
| `CLOUDFRONT_DISTRIBUTION_ID` | `<DISTRIBUTION_ID>` |
| `SITE_URL` | `https://<CLOUDFRONT_DOMAIN>` |
| `MAIL_SERVER` | e.g. `smtp.gmail.com` |
| `MAIL_PORT` | e.g. `465` |
| `MAIL_FROM` | e.g. `ci@yourdomain.com` |
| `MAIL_TO` | address(es) to notify, comma-separated |

**Secrets** tab (actual credentials — never as variables):

| Name | Value |
|---|---|
| `MAIL_USERNAME` | SMTP username |
| `MAIL_PASSWORD` | SMTP password / app password |

Never create `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` — the whole point
of the OIDC role is that no long-lived AWS key ever touches GitHub.

---

## 13. The pipeline — triggers, jobs, stages

File: [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml). One
workflow, five jobs, run in this order:

```text
push to any branch, or a pull request
        |
   [validate] -> parses JS, lints HTML, checks required files exist
        |
   [package]  -> builds dist/, uploads as a workflow artifact (30-day retention)
        |
   [deploy]   -> ONLY on main, ONLY after "production" environment is approved
        |         assumes AWS role via OIDC, s3 sync, cloudfront invalidation
        |
   [verify]   -> curls the live site, checks title + hero asset
        |
   [notify]   -> always runs on main; emails success or failure
```

**Triggers** (`on:` block): every push to every branch and every pull request
runs `validate`/`package` (catches problems before merge). Only a push that
lands on `main` (i.e. a merged PR) reaches `deploy`/`verify`/`notify`.

**Build fail → email**: `notify` job checks `needs.*.result` across
`validate`, `package`, `deploy`, `verify` — if any failed, it sends the
failure email (subject `FAILED: ...`) via `dawidd6/action-send-mail@v3` using
the `MAIL_*` secrets/variables from step 12.

**Deploy success → email**: same job, opposite branch of the `if:` —
if nothing failed or got cancelled, it sends the success email (subject
`SUCCESS: ...`) with the run link and site URL.

**Manual approval**: the `deploy` job's `environment: production` is what
pauses the run — GitHub blocks it until a required reviewer (step 11)
clicks **Review deployments → Approve and deploy** on the run page.

---

## 14. First deployment, start to finish

1. Push code to `main` (step 2) or merge a first PR into it.
2. Watch the **Actions** tab: `validate` → `package` run automatically.
3. `deploy` shows **Waiting**. Open the run → **Review deployments** →
   check `production` → **Approve and deploy**.
4. `deploy` runs: assumes the IAM role, syncs `dist/` to S3, invalidates
   CloudFront.
5. `verify` runs: curls the site, confirms title + hero image.
6. `notify` sends the success email.
7. Open `https://<CLOUDFRONT_DOMAIN>` in a browser — confirm it's live.

## 15. Ongoing changes (day 2+)

Repeat the branch → PR → merge flow from step 4. Every merge to `main`
re-triggers `deploy` (after approval), `verify`, and `notify` automatically.
No manual AWS console work needed again unless infrastructure itself
changes.

---

## 16. Rollback

No special pipeline button — rollback is just "redeploy the last known-good
commit" through the same pipeline:

```bash
git log --oneline          # find the last good commit, and the bad one
git revert <BAD_COMMIT_SHA>
git push origin main
```

The revert commit runs through `validate → package → deploy → verify` like
any other change. Approve the `production` environment again when prompted.
CloudFront invalidation in the `deploy` job means the rollback is visible as
soon as the invalidation completes — no stale cache left behind.

(S3 versioning from step 5.5 is a secondary safety net — you can restore a
prior object version directly in the S3 console if a Git-based rollback
isn't possible for some reason, but Git revert is the primary path.)

## 17. CloudFront invalidation — what happens and why

Every successful `deploy` run ends with:

```bash
aws cloudfront create-invalidation --distribution-id <DISTRIBUTION_ID> --paths "/*"
aws cloudfront wait invalidation-completed --distribution-id <DISTRIBUTION_ID> --id <INVALIDATION_ID>
```

Without this, CloudFront's edge caches keep serving the previous deployment
for up to a day (the asset cache TTL) even though S3 already has the new
files. The `wait` call blocks the job until invalidation is confirmed
complete, so `verify` never races against a half-invalidated cache.

## 18. Post-deploy checklist

- [ ] `https://<CLOUDFRONT_DOMAIN>` returns `200` and the right page title
- [ ] Direct S3 URL (`https://<S3_BUCKET>.s3.<region>.amazonaws.com/index.html`)
      returns `403`
- [ ] HTTP requests redirect to HTTPS
- [ ] Security headers present (`Strict-Transport-Security`,
      `X-Content-Type-Options`, etc.)
- [ ] A random unknown path returns your `index.html` with `200`, not a raw
      CloudFront error page (only if step 8b was configured)
- [ ] `production` environment shows the run awaiting/received approval
- [ ] Success or failure email actually arrived

See [`docs/DEPLOYMENT_RUNBOOK.md`](docs/DEPLOYMENT_RUNBOOK.md) for deeper
troubleshooting on any of the above.
