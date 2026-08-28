#!/usr/bin/env bash
# =============================================================================
# 05_verify_clean.sh  -  Confirm NO secrets remain in the REWRITTEN history.
#
# Cross-checks the cleaned repo with BOTH scanners + a raw grep over all blobs
# (the raw grep catches anything the scanners might have missed).
#
# Usage:
#     bash 05_verify_clean.sh <clean-clone-path> [extra patterns ...]
#
# Optional trailing args are extra regex patterns to grep for (e.g. your actual
# secret values). Anything found = cleanup was INCOMPLETE.
# =============================================================================
set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
say()  { printf "${GREEN}[verify]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[verify]${NC} %s\n" "$*"; }
err()  { printf "${RED}[verify]${NC} %s\n" "$*"; }

REPO="${1:?Usage: bash 05_verify_clean.sh <clean-clone-path> [patterns...]}"
shift
EXTRA_PATTERNS=("$@")
[ -d "$REPO" ] || { err "'$REPO' not a directory."; exit 1; }

SCAN_DIR="$(cd "$(dirname "$0")" && pwd)/scans"
REPO_NAME="$(basename "$REPO")"
PASS=1

echo "=================================================================="
printf "${GREEN}Verifying clean history: %s${NC}\n" "$REPO"
echo "=================================================================="

# --- 1. gitleaks re-scan ------------------------------------------------------
say "[1/4] gitleaks re-scan ..."
GL_REPORT="$SCAN_DIR/${REPO_NAME}__verify_gitleaks.json"
# shellcheck disable=SC2086
gitleaks detect --source "$REPO" --report-format json \
    --report-path "$GL_REPORT" >/dev/null 2>&1
GL_COUNT=$(jq '. | length' "$GL_REPORT" 2>/dev/null || echo 0)
if [ "${GL_COUNT:-0}" -gt 0 ]; then
  warn "  gitleaks still finds ${GL_COUNT} secret(s)! Incomplete cleanup."
  jq -r '.[] | "    [\(.RuleID)] \(.File):\(.StartLine) :: \(.Secret)"' "$GL_REPORT" 2>/dev/null | head -40
  PASS=0
else
  say "  gitleaks: CLEAN (0 findings)"
fi

# --- 2. trufflehog re-scan (working tree) -------------------------------------
say "[2/4] trufflehog scan of working tree ..."
TH_REPORT="$SCAN_DIR/${REPO_NAME}__verify_trufflehog.json"
trufflehog git "file://$REPO" --only-verified --json > "$TH_REPORT" 2>/dev/null || true
TH_COUNT=$(wc -l < "$TH_REPORT" 2>/dev/null || echo 0)
if [ "${TH_COUNT:-0}" -gt 0 ]; then
  warn "  trufflehog still finds ${TH_COUNT} verified secret(s)! Incomplete cleanup."
  jq -r 'select(.DetectorName != null) | "    \(.DetectorName): \(.Raw // "?")"' "$TH_REPORT" 2>/dev/null | sort -u | head -40
  PASS=0
else
  say "  trufflehog: CLEAN (0 verified findings)"
fi

# --- 3. Raw grep over EVERY blob in history (catches anything missed) --------
say "[3/4] raw grep across all blobs ..."
BLOB_TMP="$(mktemp)"
# Dump all unique blob contents (all history) and scan them.
git -C "$REPO" rev-list --objects --all 2>/dev/null | git -C "$REPO" cat-file --batch-check='%(objectname) %(objecttype)' 2>/dev/null | \
  awk '$2=="blob"{print $1}' | while read -r oid; do
    git -C "$REPO" cat-file blob "$oid" 2>/dev/null
    echo ""
  done > "$BLOB_TMP"

PATTERNS=(AKIA[0-9A-Z]{16} 'sk-[A-Za-z0-9]{20,}' 'gh[pousr]_[A-Za-z0-9_]{20,}' \
          '-----BEGIN [A-Z ]*PRIVATE KEY-----' 'xox[baprs]-[A-Za-z0-9-]{10,}' \
          'AIza[0-9A-Za-z_-]{35}' 'password\s*=\s*[^ ]+' 'passwd\s*[:=]\s*.+' \
          'PASSWORD\s*[:=]\s*.+' 'secret\s*[:=]\s*.+' 'token\s*[:=]\s*.+' \
          'api[_-]?key\s*[:=]\s*.+')
PATTERNS+=("${EXTRA_PATTERNS[@]}")

FOUND_BLOB=0
for pat in "${PATTERNS[@]}"; do
  if rg -in --no-filename "$pat" "$BLOB_TMP" >/dev/null 2>&1; then
    warn "  Pattern still present in history:  $pat"
    rg -in --no-filename -m3 "$pat" "$BLOB_TMP" 2>/dev/null | while read -r l; do
      printf "      %s\n" "$l" | head -c 300; echo ""
    done
    PASS=0
    FOUND_BLOB=1
  fi
done
[ "$FOUND_BLOB" -eq 0 ] && say "  raw grep: no common secret patterns found across history"

# --- 4. scan reflog / pack for any lingering refs -----------------------------
say "[4/4] check for dangling refs/reflogs referencing old secrets ..."
DANGLING=0
if git -C "$REPO" reflog show --all 2>/dev/null | grep -qiE 'secret|password|token|AKIA|PRIVATE KEY'; then
  warn "  reflog still references secret-ish content. Run expiry again:"
  warn "    git -C '$REPO' reflog expire --expire=now --all"
  warn "    git -C '$REPO' gc --prune=now --aggressive"
  PASS=0; DANGLING=1
fi
[ "$DANGLING" -eq 0 ] && say "  reflog: clean"

rm -f "$BLOB_TMP"

echo ""
echo "=================================================================="
if [ "$PASS" -eq 1 ]; then
  printf "${GREEN}  RESULT: HISTORY IS CLEAN. Proceed to push.${NC}\n"
  echo "=================================================================="
  exit 0
else
  printf "${RED}  RESULT: SECRETS STILL PRESENT. Re-run 04 with more/stronger${NC}\n"
  printf "${RED}  strategies (strip file / glob / replace-value), then re-run 05.${NC}\n"
  echo "=================================================================="
  exit 1
fi
