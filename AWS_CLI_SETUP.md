# AWS CLI Setup — Install, IAM User, Access Key, Configure

Full steps for setting up AWS CLI on your machine with an IAM user and
access key, for running the manual console/CLI steps in
[Start.md](Start.md). Windows-focused (this machine).

**Note on terminology:** an *access key* attaches to an IAM **user**, not an
IAM **role**. The IAM **role** used by GitHub Actions (`Start.md` steps 9–10,
`GitHubBmwX6ProductionDeployRole`) is assumed via OIDC and never gets an
access key — that's the whole point of it. This guide creates a separate IAM
**user** so you personally can run `aws` commands from this machine.

---

## 1. Download and install AWS CLI v2

**Option A — official MSI installer (recommended):**

1. Download: https://awscli.amazonaws.com/AWSCLIV2.msi
2. Run the downloaded `AWSCLIV2.msi`, click through the installer (defaults
   are fine), finish.
3. Close and reopen your terminal so `PATH` picks it up.

**Option B — winget (PowerShell):**

```powershell
winget install -e --id Amazon.AWSCLI
```

**Verify install:**

```powershell
aws --version
```

Expect something like `aws-cli/2.x.x Python/3.x.x Windows/...`.

---

## 2. Create an IAM user for CLI access (console)

Do this signed in as the AWS account root user or an existing admin — not
with the CLI yet, since you have no keys.

1. AWS Console → **IAM → Users → Create user**.
2. User name: e.g. `<your-name>-cli`.
3. **Do not** select "Provide user access to the AWS Management Console" —
   this user is CLI-only.
4. Permissions options → **Attach policies directly**.
   - For personal/admin use on your own account: attach `AdministratorAccess`.
   - For least privilege instead (recommended once the project is running):
     attach only what you actually need — e.g. `AmazonS3FullAccess`,
     `CloudFrontFullAccess`, `IAMFullAccess` — or a scoped custom policy
     covering just S3/CloudFront/IAM actions used in `Start.md`.
5. Create user.
6. (Strongly recommended) Enable MFA on this user: user → **Security
   credentials** → **Assign MFA device**.

---

## 3. Create the access key

1. IAM → **Users** → select the user from step 2.
2. **Security credentials** tab → **Access keys** → **Create access key**.
3. Use case: **Command Line Interface (CLI)**.
4. Check the confirmation box, **Create access key**.
5. **Download the .csv** (or copy both values now) — this is the only time
   the secret key is shown.

You now have:

```text
Access key ID:     AKIA...
Secret access key: <shown once>
```

---

## 4. Run `aws configure`

```powershell
aws configure
```

Enter when prompted:

```text
AWS Access Key ID [None]: <paste Access Key ID>
AWS Secret Access Key [None]: <paste Secret Access Key>
Default region name [None]: us-east-1
Default output format [None]: json
```

This writes to `%USERPROFILE%\.aws\credentials` and
`%USERPROFILE%\.aws\config`.

**Multiple profiles** (if you manage more than one AWS account/role):

```powershell
aws configure --profile <profile-name>
```

Use it later with `--profile <profile-name>` on any `aws` command, or set
`$env:AWS_PROFILE = "<profile-name>"` for the session.

---

## 5. Verify

```powershell
aws sts get-caller-identity
```

Expect:

```json
{
    "UserId": "AIDA...",
    "Account": "<AWS_ACCOUNT_ID>",
    "Arn": "arn:aws:iam::<AWS_ACCOUNT_ID>:user/<your-name>-cli"
}
```

If this returns your user ARN, the CLI is fully configured and ready for
every `aws ...` command in `Start.md`.

---

## 6. Security cleanup — don't skip

- Delete the downloaded `.csv` from Downloads after saving the keys in a
  password manager. Anyone with those two values has full account access
  under whatever policy you attached.
- Never commit `~/.aws/credentials`, paste keys into chat, or put them in
  any file inside this repo.
- Rotate the access key periodically: IAM → Users → user → Security
  credentials → **Deactivate**/**Delete** old key after creating and
  switching to a new one.
- If a key ever leaks (terminal share, screenshot, committed by accident):
  deactivate it immediately in IAM, then delete it, then create a new one.
- Long term, prefer AWS IAM Identity Center (SSO) or short-lived
  role-assumption over a permanent access key sitting on a laptop — this
  guide uses a static key because it's the fastest path to a working CLI
  today.
