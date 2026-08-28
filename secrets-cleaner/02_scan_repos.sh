#!/usr/bin/env bash
# =============================================================================
# 02_scan_repos.sh  -  DETECT all secrets across ALL commits of your repos.
#
# Uses BOTH gitleaks (fast, full-history) and trufflehog (verifies live secrets).
# Outputs findings into ./scans/ for later use in step 04.
#
# Usage:
#     bash 02_scan_repos.sh                     # interactive: pick repos
#     bash 02_scan_repos.sh /path/to/repo       # scan one repo non-interactive
#     bash 02_scan_repos.sh --autodetect        # scan all git repos in ~
# =============================================================================
set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
say()  { printf "${GREEN}[scan]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[scan]${NC} %s\n" "$*"; }
err()  { printf "${RED}[scan]${NC} %s\n" "$*"; }

SCAN_DIR="$(cd "$(dirname "$0")" && pwd)/scans"
mkdir -p "$SCAN_DIR"

# --- decide which repos to scan ---------------------------------------------
REPOS=()
AUTODETECT=false
if [ "${1:-}" = "--autodetect" ]; then
  AUTODETECT=true
  while IFS= read -r d; do REPOS+=("$d"); done < <(find "$HOME" -type d -name .git 2>/dev/null | sed 's#/.git$##')
  say "Autodetected ${#REPOS[@]} repos under \$HOME."
elif [ "${1:-}" ]; then
  REPOS=("$1")
else
  if [ -f "./helpers/list_repos.sh" ]; then
    bash ./helpers/list_repos.sh
  else
    warn "No list_repos.sh helper found; add repos to scan manually below."
  fi
  # Fallback: interactive picker
  echo ""
  while true; do
    read -rp "  Enter a repo path to scan (or <blank> to finish): " p
    [ -z "$p" ] && break
    [ -d "$p/.git" ] || [ -f "$p/HEAD" ] || { err "'$p' is not a git repo."; continue; }
    REPOS+=("$p")
  done
fi

[ "${#REPOS[@]}" -eq 0 ] && err "No repos selected. Nothing to do." && exit 1

# --- scan each repo ----------------------------------------------------------
for REPO in "${REPOS[@]}"; do
  REPO_FULL="$(cd "$REPO" && pwd)"
  REPO_NAME="$(basename "$REPO_FULL")"
  echo ""
  echo "=================================================================="
  printf "${CYAN}Scanning: %s${NC}\n" "$REPO_NAME  ($REPO_FULL)"
  echo "=================================================================="

  # Make a temp shallow-unpacked WORK COPY (read-only source for scanners)
  TMP_CLONE="$(mktemp -d)/$REPO_NAME"
  say "Creating work copy for scanning: $TMP_CLONE"
  git clone --mirror "$REPO_FULL" "$TMP_CLONE.git" >/dev/null 2>&1 || {
    err "Failed to mirror clone $REPO_NAME, skipping."; continue; }
  WORK="$TMP_CLONE.git"

  # ---- Gitleaks: full history, all branches & tags ----------------------
  say "Running gitleaks (full history)..."
  GL_REPORT="$SCAN_DIR/${REPO_NAME}__gitleaks.json"
  # shellcheck disable=SC2086
  gitleaks detect --source "$WORK" --report-format json --report-path "$GL_REPORT" \
      >/dev/null 2>&1
  GL_COUNT=0
  [ -s "$GL_REPORT" ] && GL_COUNT=$(jq '. | length' "$GL_REPORT" 2>/dev/null || echo 0)
  say "gitleaks found ${GL_COUNT} finding(s) -> $GL_REPORT"
  if [ "${GL_COUNT:-0}" -gt 0 ]; then
    # Human readable summary
    echo "  --- gitleaks summary ---"
    jq -r '.[] | "  [\(.RuleID)] \(.File) @ \(.StartLine): \(.Secret) in commit \(.Commit[:7])"' \
        "$GL_REPORT" 2>/dev/null | head -80 || true
  fi

  # ---- TruffleHog: deep + verify live secrets ----------------------------
  say "Running trufflehog (deep + verification)..."
  TH_REPORT="$SCAN_DIR/${REPO_NAME}__trufflehog.json"
  # Scan ALL refs (branches + tags) with verification.
  trufflehog git "file://$WORK" --only-verified --json \
      > "$TH_REPORT" 2>/dev/null || true
  TH_COUNT=$(wc -l < "$TH_REPORT" 2>/dev/null || echo 0)
  say "trufflehog found ${TH_COUNT} VERIFIED finding(s) -> $TH_REPORT"
  if [ "${TH_COUNT:-0}" -gt 0 ]; then
    echo "  --- trufflehog VERIFIED leaks (MUST ROTATE + PURGE) ---"
    jq -r 'select(.DetectorName != null) | "  [VERIFIED \(.DetectorName)] file=\(.SourceMetadata.Data.Git.file // "?") commit=\(.SourceMetadata.Data.Git.commit // "?") secret=\(.Raw // "?")"' \
        "$TH_REPORT" 2>/dev/null | sort -u | head -60 || true
  else
    echo "  (no live/verified secrets found by trufflehog)"
  fi

  echo ""
  if [ "${GL_COUNT:-0}" -gt 0 ] || [ "${TH_COUNT:-0}" -gt 0 ]; then
    warn ">>> Findings detected in '$REPO_NAME'. Clean it with step 03 + 04. <<<"
  else
    say "No secrets detected in '$REPO_NAME'. (Double-check with 05_verify_clean.sh.)"
  fi
done

echo ""
say "Scan complete. All JSON reports saved in: $SCAN_DIR"
say "Next: pick one repo and run   bash 03_prepare_repo.sh <repo-path>"
