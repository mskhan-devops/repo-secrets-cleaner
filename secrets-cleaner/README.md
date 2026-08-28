# Secrets Cleaner — Fully Automated Git History Secret Removal

A step-by-step, multi-tool toolkit to **find and completely remove** passwords,
API keys, tokens, and any other secrets from the **entire commit history** of
your repositories, so they never reach GitHub.

This is a *belt-and-braces* pipeline: it runs **multiple independent scanners**
(Gitleaks + TruffleHog + raw blob grep) and then **rewrites history** to purge
everything, then **verifies** the result, then **pushes**, then **guards** the
repo so it can't happen again.

---

## The Golden Rule (IMPORTANT)

> **Cleaning history is hygiene. ROTATING the secret is the real fix.**
>
> If a secret was EVER pushed, anyone or any crawler may already possess it.
> Rewriting history does not un-expose it. **Always rotate/revoke every real
> credential at its source** (AWS console, GitHub, Slack, Stripe, etc.) even
> after you purge it from history.

---

## What you get

| Script | Purpose |
|--------|---------|
| `00_preflight.sh` | Install all prerequisites (Gitleaks, TruffleHog, git-filter-repo) |
| `01_intro.sh` | Prints the overview + safety warnings (run once) |
| `02_scan_repos.sh` | **DETECT** secrets across ALL commits (2 scanners) |
| `03_prepare_repo.sh` | Fresh mirror clone + backup + drafted remediation plan |
| `04_purge_secrets.sh` | **REWRITE** history to remove the secrets (git-filter-repo) |
| `05_verify_clean.sh` | **CONFIRM** nothing remains (2 scanners + raw blob grep) |
| `06_push_clean.sh` | Force-push the clean history (all branches + tags) |
| `07_guard.sh` | Install pre-commit/pre-push hooks + harden `.gitignore` |

**Helpers** (in `./helpers/`): repo picker, replacements-file builder, `.gitignore`
hardener, hook installer.

---

## Prerequisites

- **OS:** Linux / macOS / WSL. (Scripts are bash. Windows users: use WSL or Git Bash.)
- **git** (required)
- **Internet** once during install (to download scanners)

`00_preflight.sh` auto-installs everything else via `homebrew`, `apt`, `dnf`,
`go`, or direct binary download (works on Mac + Linux + x86/arm).

---

## Quick Start (fast path)

```bash
cd secrets-cleaner

# 1. Install tools (once per machine)
bash 00_preflight.sh

# 2. Read the golden rules
bash 01_intro.sh

# 3. Scan a repo / several repos  (pick path, multiple allowed)
bash 02_scan_repos.sh /path/to/my/repo
bash 02_scan_repos.sh --autodetect     # optional: scan all repos under $HOME

# 4. Prepare ONE repo (fresh clone + backup + plan) -> gives you $CLEAN
bash 03_prepare_repo.sh /path/to/my/repo
```

Step 4 prints the exact `$CLEAN` path (e.g. `work/my_repo__clean`) and a
`backups/<repo>__remediation_plan.txt`. **Review that plan, rotate every real
secret, then:**

```bash
# 5. Purge: strip files / replace secret values from ALL history
bash 04_purge_secrets.sh work/my_repo__clean --strip-glob '*.env'
bash 04_purge_secrets.sh work/my_repo__clean --strip-file config/secrets.yaml
bash 04_purge_secrets.sh work/my_repo__clean --replace-file backups/secrets_replaced.txt
#    (combine as many --strip-file/--strip-glob/--replace-value/--replace-file as needed)

# 6. Verify nothing remains (repeat until it passes)
bash 05_verify_clean.sh work/my_repo__clean

# 7. Force-push the clean history (ALL branches + tags)
bash 06_push_clean.sh work/my_repo__clean

# 8. Guard the working copy so it never happens again
bash 07_guard.sh /path/to/my/repo
```

---

## Step-by-step detail

### Step 1 — Install tools
```bash
bash 00_preflight.sh
```
Installs and verifies: **gitleaks**, **trufflehog**, **git-filter-repo**.
Exit with nothing MISSING before continuing.

### Step 2 — Scan (detect everything)
```bash
bash 02_scan_repos.sh /path/to/repo
```
- **Gitleaks** → fast full-history scan of every commit/branch/tag → JSON report
  in `scans/`.
- **TruffleHog** → deep scan with **live verification** → flags EDITOR VERIFIED
  secrets (must rotate + purge).
- Reports saved to `scans/<repo>__gitleaks.json` and `...__trufflehog.json`.

### Step 3 — Prepare (one repo at a time)
```bash
bash 03_prepare_repo.sh /path/to/repo
```
- Creates a **mirror clone** in `work/<repo>__clean` (never touches your daily copy).
- Creates a **full backup bundle** in `backups/<repo>__original_<stamp>.bundle`.
- Drafts `backups/<repo>__remediation_plan.txt` listing detected secrets.

### Step 4 — Purge (rewrite history)
```bash
bash 04_purge_secrets.sh work/<repo>__clean <strategies...>
```
Runs `git-filter-repo` (the modern, Git-recommended tool) over **every commit**.
Strategies (all can be combined in one command):
- `--strip-file <path>` — remove one file everywhere it ever existed.
- `--strip-glob '<glob>'` — remove files matching a glob (e.g. `'*.env'`).
- `--replace-value <secret>` — replace one exact secret string everywhere.
- `--replace-file <file>` — use a `secret==>REDACTED` list file (build one with
  `helpers/generate_replacements.sh`).

Then it expires reflogs + garbage-collects to physically erase the objects.

### Step 5 — Verify (must pass before pushing)
```bash
bash 05_verify_clean.sh work/<repo>__clean [extra-secret-patterns...]
```
Cross-check with **gitleaks**, **trufflehog**, and a **raw grep across every
blob** (catches what regex scanners miss). Exit code 0 = clean, safe to push.
If it finds something, go back to Step 4 with stronger strategies.

### Step 6 — Push
```bash
bash 06_push_clean.sh work/<repo>__clean          # or add --dry-run first
```
Force-pushes **all branches + all tags**. After this:
- Everyone must **re-clone** (old clones keep old secrets).
- If it was ever public, open a GitHub/GitLab support ticket to purge cached
  PR diffs / forks / search indexes.

### Step 7 — Guard (prevent recurrence)
```bash
bash 07_guard.sh /path/to/my/repo
```
- Installs a **gitleaks pre-commit hook** (blocks secrets in staged changes).
- Hardens **.gitignore** so `.env`, keys, certs, secrets are never tracked.
- Recommended: move secrets to a **secrets manager / env vars / SOPS** — never git.

---

## Advanced / Tips

- **Secret copied across many files?** Use `--replace-file` with
  `helpers/generate_replacements.sh` to scrub the exact value everywhere.
- **Best pre-push protection:** uncomment the two lines in
  `work/.git/hooks/pre-push` (or in each developer's clone) to block pushes that
  contain secrets, defeating `--no-verify` bypass.
- **Very large repos:** gitleaks+trufflehog can be slow. Run scans overnight or
  on a CI runner with a long timeout.
- **Multiple repos:** run Steps 2→6 once per repo. The `scans/`, `work/`,
  `backups/` folders keep each repo's artifacts separate.

---

## Safety & cleanup checklist

1. ⬜ Rotate every real secret at the source.
2. ⬜ Verify clean (`05`) returns exit 0.
3. ⬜ Force-push all branches + tags (`06`).
4. ⬜ Tell collaborators to re-clone.
5. ⬜ Re-add `origin` remote if removed (Step 4 warns; `git remote add origin URL`).
6. ⬜ After a successful push & confirmation, **delete the backup bundles in
   `backups/`** (they contain the old secrets) and `work/` clones.
7. ⬜ If repo was ever public → GitHub/GitLab support ticket; assume exposure.
8. ⬜ Install `07_guard.sh` on every developer's clone.

---

## Notes
- All scanners and the rewrite tool are **open source** (MIT / Apache-2.0 /
  AGPL-3.0 / GPL). `git-filter-repo` is the tool officially recommended by Git.
- This toolkit is provided for legitimate security remediation of repositories
  you own. Always rotate credentials — history rewriting is not a substitute.
