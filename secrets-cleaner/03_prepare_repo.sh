#!/usr/bin/env bash
# =============================================================================
# 03_prepare_repo.sh  -  Prepare ONE repo for history rewriting.
#
#   * Clones the repo fresh (mirror) so we never touch your daily working copy.
#   * Creates a timestamped backup of the original history.
#   * Drafts a remediation-plan file listing every detected secret so you can
#     review/rotate them and decide purge strategy.
#
# Usage:
#     bash 03_prepare_repo.sh /path/to/repo
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
say()  { printf "${GREEN}[prepare]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[prepare]${NC} %s\n" "$*"; }
err()  { printf "${RED}[prepare]${NC} %s\n" "$*" >&2; }

ROOT="$(cd "$(dirname "$0")" && pwd)"
WORKROOT="$ROOT/work"
SCAN_DIR="$ROOT/scans"
mkdir -p "$WORKROOT"

REPO="${1:?Usage: bash 03_prepare_repo.sh <repo-path>}"
[ -e "$REPO" ] || err "'$REPO' does not exist." && exit 1
REPO_FULL="$(cd "$REPO" && pwd)"
REPO_NAME="$(basename "$REPO_FULL")"
STAMP="$(date +%Y%m%d_%H%M%S)"

# --- 1. Fresh mirror clone into workdir --------------------------------------
SAFE="$WORKROOT/${REPO_NAME}__clean"
if [ -e "$SAFE" ]; then
  warn "A prepared dir already exists: $SAFE"
  read -rp "  Remove it and re-clone? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] && rm -rf "$SAFE" || { err "Aborted."; exit 1; }
fi
say "Mirror-cloning '$REPO_NAME' into $SAFE ..."
git clone --mirror "$REPO_FULL" "$SAFE" 2>/dev/null

# --- 2. Backup the ORIGINAL history ------------------------------------------
BACKUP="$ROOT/backups/${REPO_NAME}__original_${STAMP}.bundle"
mkdir -p "$(dirname "$BACKUP")"
say "Creating full backup bundle: $BACKUP"
git -C "$SAFE" bundle create "$BACKUP" --all 2>/dev/null
say "Backup saved. If anything goes wrong:  git clone $BACKUP <dest>"
echo "  (this backup retains ALL secrets - keep it OFF shared drives / delete after success)"

# --- 3. Draft remediation plan -----------------------------------------------
PLAN="$ROOT/backups/${REPO_NAME}__remediation_plan.txt"
: > "$PLAN"
{
  echo "=============================================================="
  echo "  Remediation plan for: $REPO_NAME"
  echo "  Generated: $(date)"
  echo "  Original-history backup: $BACKUP"
  echo ""
  echo "  ACTION REQUIRED: For every real secret below, ROTATE/REVOKE it"
  echo "  at the provider BEFORE running step 04. Then decide HOW to purge:"
  echo "    [F]ile   -> remove the whole file from history"
  echo "    Value    -> replace the exact secret string everywhere"
  echo ""
  echo "=============================================================="
} >> "$PLAN"

# Pull findings from step-02 reports if present
for f in "$SCAN_DIR"/"${REPO_NAME}"__gitleaks.json "$SCAN_DIR"/"${REPO_NAME}"__trufflehog.json; do
  [ -s "$f" ] || continue
  echo "" >> "$PLAN"
  echo "--- findings from: $(basename "$f") ---" >> "$PLAN"
  if [[ "$f" == *trufflehog* ]]; then
    jq -r 'select(.DetectorName != null) | "VERIFIED \(.DetectorName): \(.Raw // "?")" | gsub("^VERIFIED "; "")' "$f" 2>/dev/null | sort -u >> "$PLAN" || true
  else
    jq -r '.[] | "[\(.RuleID)] \(.File):\(.StartLine) :: \(.Secret)"' "$f" 2>/dev/null | sort -u >> "$PLAN" || true
  fi
done

say "Remediation plan drafted: $PLAN"
echo ""
echo "=================================================================="
echo "  NEXT STEPS"
echo "=================================================================="
echo "  1. READ $PLAN"
echo "  2. ROTATE every real secret at its provider (AWS console, GitHub, etc)."
echo "  3. Edit the repo's working copy to remove the secrets from source"
echo "     (or let 04 do it via replacements)."
echo "  4. Run:   bash 04_purge_secrets.sh $SAFE"
echo "=================================================================="
