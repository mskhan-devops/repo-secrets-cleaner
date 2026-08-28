#!/usr/bin/env bash
# =============================================================================
# 07_guard.sh  -  PREVENT secrets ever being committed again.
#
#   * Installs gitleaks pre-commit + pre-push hooks on the repo's working copy.
#   * Calls helpers/harden_gitignore.sh to append common secret-file patterns.
#   * (Optional) writes a .gitignore rule for .env and key files.
#
# Usage:
#     bash 07_guard.sh <repo-working-copy-path>
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
say()  { printf "${GREEN}[guard]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[guard]${NC} %s\n" "$*"; }
err()  { printf "${RED}[guard]${NC} %s\n" "$*" >&2; }

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="${1:?Usage: bash 07_guard.sh <repo-working-copy-path>}"
[ -d "$REPO/.git" ] || { err "'$REPO' is not a git working copy (no .git dir)."; exit 1; }

command -v gitleaks >/dev/null 2>&1 || { err "gitleaks not installed. Run 00_preflight.sh"; exit 1; }

# --- 1. install hooks ---------------------------------------------------------
WINNER="$(cd "$ROOT" && bash helpers/install_hooks.sh "$REPO")"
say "$WINNER"

# --- 2. harden .gitignore -----------------------------------------------------
say "Hardening .gitignore..."
bash "$ROOT/helpers/harden_gitignore.sh" "$REPO"

# --- 3. tell the user to actually MOVE secrets out of the repo -----------------
say "Guard installed on: $REPO"
echo ""
say "RECOMMENDATION: Move secrets OUT of the repo entirely. Use:"
echo "   - .env + git-secrets / SOPS / age (encrypted)   "
echo "   - A secrets manager:  1Password, Vault, AWS/GCP/Azure Secrets Managers"
echo "   - Env vars in CI/CD, never committed."
echo ""
say "Finished. Your repo now blocks secrets at commit & push time."
