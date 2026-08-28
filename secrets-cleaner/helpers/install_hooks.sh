#!/usr/bin/env bash
# =============================================================================
# helpers/install_hooks.sh  -  Add gitleaks pre-commit + pre-push hooks.
#
# The pre-commit hook blocks secrets in staged changes.
# A pre-push hook (optional) re-checks everything being pushed. Uncomment the
# block at the bottom to enable it (prevents --no-verify abuse on local push).
#
# Usage:  bash install_hooks.sh <repo-working-copy-path>
# =============================================================================
set -euo pipefail

REPO="${1:?Usage: bash install_hooks.sh <repo-working-copy-path>}"
[ -d "$REPO/.git" ] || { echo "ERROR: not a git working copy: $REPO" >&2; exit 1; }
command -v gitleaks >/dev/null 2>&1 || { echo "ERROR: gitleaks not installed" >&2; exit 1; }

HOOKS_DIR="$REPO/.git/hooks"
mkdir -p "$HOOKS_DIR"

# --- pre-commit ---------------------------------------------------------------
cat > "$HOOKS_DIR/pre-commit" <<'EOF'
#!/usr/bin/env bash
# gitleaks pre-commit: block secrets in staged changes
gitleaks protect --staged --verbose
if [ $? -ne 0 ]; then
  echo ">>> SECRET DETECTED. Commit blocked. Remove the secret and re-stage."
  exit 1
fi
EOF
chmod +x "$HOOKS_DIR/pre-commit"

# --- pre-push (commented by default for convenience) --------------------------
cat > "$HOOKS_DIR/pre-push" <<'EOF'
#!/usr/bin/env bash
# gitleaks pre-push: block secrets in commits about to be pushed.
# Uncomment the two lines below to ENABLE this (prevents pushing any history
# that contains a secret). Requires gitleaks installed by 00_preflight.sh.
#
# gitleaks protect --verbose
# exit $?
EOF
chmod +x "$HOOKS_DIR/pre-push"

echo "Installed gitleaks pre-commit hook (active) + pre-push hook (template) in:"
echo "  $HOOKS_DIR"
echo "(To enable push-blocking, uncomment the lines in .git/hooks/pre-push)"
