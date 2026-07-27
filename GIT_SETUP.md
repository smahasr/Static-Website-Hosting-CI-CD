# Git & GitHub Setup — Install, Configure, Auth, Test

Step by step: install Git, set your identity, connect to GitHub, verify
which user Git thinks you are. Windows-focused (this machine).

---

## 1. Install Git

**Check if already installed:**

```powershell
git --version
```

If that prints a version, skip to step 2.

**Install (if missing):**

- Download: https://git-scm.com/download/win, run installer, defaults are
  fine.
- Or via winget: `winget install -e --id Git.Git`

Close and reopen your terminal after install.

---

## 2. Set your Git identity

```powershell
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

Use the **same email as your GitHub account** (or one added to it under
GitHub → Settings → Emails) — otherwise commits won't link to your profile.

**Per-repo override** (different identity just for one project):

```powershell
cd path\to\repo
git config user.name "Work Name"
git config user.email "work@example.com"
```

Local config (no `--global`) always wins over global config inside that repo.

---

## 3. Check which Git user is configured (testing)

**Effective identity for the current folder** (local override if set, else
global):

```powershell
git config user.name  or git config --global user.name
git config user.email or git config --global user.email
```

**See where each value comes from and every config source at once:**

```powershell
git config --list --show-origin
```

**Global-only values:**

```powershell
git config --global --list
```

**Confirm what a real commit would record right now:**

```powershell
git var GIT_AUTHOR_IDENT
```

Prints `Name <email> timestamp` — the exact author line Git would stamp on
your next commit.

**After you've made commits, confirm authorship in history:**

```powershell
git log --format="%h %an <%ae>" -5
```

---

## 4. Connect to GitHub — choose SSH or HTTPS

### Option A — SSH (recommended, no token to retype)

1. Generate a key:

```powershell
ssh-keygen -t ed25519 -C "you@example.com"
```

Accept the default file location, set a passphrase (recommended).

2. Start the agent and add the key:

```powershell
Get-Service ssh-agent | Set-Service -StartupType Automatic
Start-Service ssh-agent
ssh-add $env:USERPROFILE\.ssh\id_ed25519
```

3. Copy the public key:

```powershell
Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub | clip
```

4. GitHub → **Settings → SSH and GPG keys → New SSH key** → paste → save.

5. Test the connection:

```powershell
ssh -T git@github.com
```

Expect: `Hi <username>! You've successfully authenticated...`

6. Clone/set remotes with the SSH URL form:

```powershell
git clone git@github.com:<OWNER>/<REPO>.git
```

### Option B — HTTPS with a Personal Access Token (PAT)

1. GitHub → **Settings → Developer settings → Personal access tokens →
   Fine-grained tokens → Generate new token**. Scope it to the repo(s) you
   need, permission `Contents: Read and write` (add `Workflows` too if you'll
   edit `.github/workflows/*` through git push).
2. Copy the token now — shown once.
3. Clone with the HTTPS URL:

```powershell
git clone https://github.com/<OWNER>/<REPO>.git
```

4. On first push, Git prompts for username + password — use the token as
   the password. Windows Credential Manager caches it after that so you
   won't be asked again.

**Never commit the token, paste it into chat, or put it in any file in the
repo.**

---

## 5. Point an existing local repo at GitHub

If you already have the folder locally and just need to attach it to a
GitHub repo:

```powershell
cd path\to\repo
git remote add origin git@github.com:<OWNER>/<REPO>.git   # SSH
# or
git remote add origin https://github.com/<OWNER>/<REPO>.git  # HTTPS

git remote -v          # confirm it's set correctly
git branch -M main
git push -u origin main
```

---

## 6. End-to-end test

```powershell
git config user.name
git config user.email
git remote -v
git status
git log --format="%h %an <%ae> %s" -3
```

All five should show: the right name/email, the right remote URL, a clean
or expected working tree, and recent commits authored by you. If `git push`
succeeds and the commit shows up on GitHub under your avatar, auth and
identity are both correct.

---

## 7. Optional: GitHub CLI (`gh`)

Not required for git push, but useful for managing secrets/variables/
environments from the terminal instead of the web UI (see `Start.md`).

```powershell
winget install -e --id GitHub.cli
gh auth login
gh auth status
```

`gh auth status` is the `gh`-side equivalent of step 3 — confirms which
GitHub account you're authenticated as.

---

## 8. Multiple GitHub accounts on one machine (optional)

If you need a personal and a work GitHub account side by side:

- Use per-repo `user.name`/`user.email` (step 2) in every repo — never rely
  on `--global` matching both.
- For SSH, add a second key and an `~/.ssh/config` entry with a distinct
  `Host` alias per account, then clone using that alias instead of
  `github.com` directly.
- For HTTPS, Windows Credential Manager only holds one GitHub credential at
  a time per remote URL — switch via `gh auth switch` if using `gh`, or
  re-authenticate when prompted.
