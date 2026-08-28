#!/usr/bin/env bash
# =============================================================================
# 06_push_clean.sh  -  Force-push the REWRITTEN clean history to the remote.
#
# Pushes ALL branches + ALL tags. Only run AFTER step 05 confirmed CLEAN.
#
# IMPORTANT: This rewrites the shared/hosted history.
#   * All collaborators MUST re-clone afterwards (their copies keep old secrets).
#   * If the repo was ever PUBLIC, contact GitHub/GitLab support to purge cached
#     PR diffs & search indexes.
#
# Usage:
#     bash 06_push_clean.sh <clean-clone-path>
#     bash 06_push_clean.sh <clean-clone-path> --dry-run   (show refs, don't push)
# =============================================================================
set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
say()  { printf "${GREEN}[push]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[push]${NC} %s\n" "$*"; }
err()  { printf "${RED}[push]${NC} %s\n" "$*" >&2; }

REPO="${1:?Usage: bash 06_push_clean.sh <clean-clone-path> [--dry-run]}"
[ -d "$REPO" ] || { err "'$REPO' not a directory."; exit 1; }

DRY=0
[ "${2:-}" = "--dry-run" ] && DRY=1

# --- ensure a remote exists ---------------------------------------------------
if ! git -C "$REPO" remote | grep -q .; then
  err "No remote configured on '${REPO}'. Add it first:"
  err "    git -C '$REPO' remote add origin <your-remote-url>"
  exit 1
fi

echo "=================================================================="
printf "Repo: %s\n" "$REPO"
echo "Remotes:"
git -C "$REPO" remote -v | sed 's/^/  /'
echo "Branches to push:"
git -C "$REPO" for-each-ref --format='  %(refname)' refs/heads | sed 's/^  refs\/heads\///'
echo "Tags to push:"
git -C "$REPO" for-each-ref --format='  %(refname)' refs/tags | sed 's/^  refs\/tags\///'
echo "=================================================================="

if [ "$DRY" -eq 1 ]; then
  say "--dry-run: showing what WOULD be pushed. Not pushing."
  exit 0
fi

warn "This will force-push ALL branches and tags (rewriting hosted history)."
read -rp "Type FORCE to proceed : " ans
[[ "$ans" == "FORCE" ]] || { err "Aborted."; exit 1; }

say "Pushing all branches (force)..."
if ! git -C "$REPO" push --force --all origin; then
  err "Branch push failed. Check remote URL / permissions."
  exit 1
fi

say "Pushing all tags (force)..."
git -C "$REPO" push --force --tags origin || { err "Tag push failed."; exit 1; }

say "Done. History pushed to remote."
echo ""
echo "  AFTERPUSH checklist (do all of these):"
echo "   1. Tell EVERY collaborator to re-clone (old clones contain old secrets)."
echo "   2. Re-add your secrets via env vars / a secrets manager, NOT in git."
echo "   3. If repo was ever public: open a GitHub/GitLab support ticket to"
echo "      purge cached copy in PR diffs, forks, and search indexes."
echo "   4. Consider deleting unreferenced forks/stargazer clones - out of reach."
echo ""
say "Prevent recurrence now:  bash 07_guard.sh <repo-working-copy>"
