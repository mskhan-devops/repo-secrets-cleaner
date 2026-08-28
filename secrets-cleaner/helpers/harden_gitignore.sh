#!/usr/bin/env bash
# =============================================================================
# helpers/harden_gitignore.sh  -  Append common secret-file patterns to
#                                 a repo's .gitignore (idempotent).
#
# Usage:  bash harden_gitignore.sh <repo-working-copy-path>
# =============================================================================
set -euo pipefail

REPO="${1:?Usage: bash harden_gitignore.sh <repo-working-copy-path>}"
[ -d "$REPO/.git" ] || { echo "ERROR: not a git working copy: $REPO" >&2; exit 1; }

GITIGNORE="$REPO/.gitignore"
touch "$GITIGNORE"

# Patterns that should NEVER be tracked, wherever they appear.
PATTERNS=(
  '.env'
  '*.env'
  '.env.*'
  '!*.env.example'
  '!*.env.template'
  '*.pem'
  '*.key'
  'id_rsa'
  'id_dsa'
  '*.cer'
  '*.p12'
  '*.pfx'
  'secrets.yml'
  'secrets.yaml'
  'secret.yaml'
  'secret.yml'
  'credentials.json'
  '.credentials'
  'google-*.json'
  '*.service-account.json'
  'service-account.json'
  'config/secrets.*'
)

ADDED=0
for pat in "${PATTERNS[@]}"; do
  # match literal line (anchored)
  if ! grep -qxF "$pat" "$GITIGNORE" 2>/dev/null; then
    printf '%s\n' "$pat" >> "$GITIGNORE"
    ADDED=$((ADDED+1))
  fi
done

if [ "$ADDED" -gt 0 ]; then
  echo "Added $ADDED new ignore pattern(s) to: $GITIGNORE"
  echo "  (You should also 'git rm --cached' any of these already tracked.)"
else
  echo ".gitignore already hardened ($ADDED new patterns)."
fi
