#!/usr/bin/env bash
# =============================================================================
# 01_intro.sh  -  Overview & golden rules. READ THIS FIRST.
#
# Run:    bash 01_intro.sh         (just prints info, makes no changes)
# =============================================================================
cat <<'EOF'
================================================================================
  SECRETS CLEANER — Golden Rules (read carefully)
================================================================================

There are TWO independent problems when a secret is committed to git:

  1) DETECTION   - The secret EXISTS somewhere in your commit history.
                    Deleting it in a new commit does NOT remove it from history.
                    It is still reachable via:  git checkout <old-sha> -- file

  2) REMEDIATION - You must REWRITE history to strip the secret from EVERY
                    commit, then ROTATE the actual credential at its source.

THE #1 RULE — ROTATE FIRST:
   History rewriting does NOT undo exposure. If a secret was ever pushed, anyone
   (or any crawler) may already have it. After cleaning history you MUST still:
      * Rotate/revoke the API key / password / token at the provider.
   Cleaning history is HYGIENE. Rotation is what actually fixes the leak.

THE PIPELINE (run in order, one repo at a time):

   Step 1  : 00_preflight.sh      -> install gitleaks/trufflehog/filter-repo
   Step 2  : 02_scan_repos.sh     -> DETECT all secrets across ALL commits
   Step 3  : 03_prepare_repo.sh   -> clone fresh, backup, draft remediation list
   Step 4  : 04_purge_secrets.sh  -> REWRITE history to remove the secrets
   Step 5  : 05_verify_clean.sh   -> confirm EVERYTHING is gone (re-scan + grep)
   Step 6  : 06_push_clean.sh     -> force-push the clean history (all refs)
   Step 7  : 07_guard.sh          -> install pre-commit/pre-push hooks so it
                                      never happens again + harden .gitignore

HELPERS (in ./helpers):

   helpers/list_repos.sh          -> interactive: point each of your repo paths
   helpers/generate_replacements.sh -> turn raw secret values into filter-repo
                                      replace-text entries input required
   helpers/harden_gitignore.sh    -> append secret-file patterns to .gitignore
   helpers/install_hooks.sh       -> write gitleaks pre-commit + pre-push hooks

================================================================================
  IMPORTANT SAFETY WARNINGS
================================================================================

  * History rewriting changes EVERY commit hash after the earliest secret.
    All collaborators MUST re-clone after you force-push.
  * ALWAYS work on a FRESH CLONE (steps 02/03 do this automatically). Never
    run filter-repo on your daily working clone.
  * Keep the backups that 03_prepare_repo.sh creates until you are 100% sure.
  * If the repo was EVER public, rewriting alone is not enough -
      rotate everything, and consider the data permanently exposed.
================================================================================
EOF
