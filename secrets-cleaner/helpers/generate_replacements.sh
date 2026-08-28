#!/usr/bin/env bash
# =============================================================================
# helpers/generate_replacements.sh  -  Build a filter-repo replacements file.
#
# Interactive: enter every raw secret value you found, one per line. Produces
# a file of "<secret>==>REDACTED" lines for  git filter-repo --replace-text .
# This is how you strip a secret that was copy-pasted into many files/paths.
#
# Usage:  bash helpers/generate_replacements.sh <output-file>
#   (output-file e.g. backups/secrets_replaced.txt)
# =============================================================================
set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
say()  { printf "${GREEN}[replace]${NC} %s\n" "$*"; }
err()  { printf "${RED}[replace]${NC} %s\n" "$*"; }

OUT="${1:?Usage: bash generate_replacements.sh <output-file>}"
OUT="$(readlink -f "$OUT" || realpath "$OUT")"

echo "Paste every RAW secret value you need to purge from history."
echo "One secret per line. Finish with an empty line or 'done'."
> "$OUT"
while IFS= read -rp "  secret> " secret; do
  [ -z "$secret" ] && break
  [ "$secret" = "done" ] && break
  # Escape for literal match in filter-repo's literal replacement mode
  printf '%s==>REDACTED\n' "$secret" >> "$OUT"
done

if [ -s "$OUT" ]; then
  say "Wrote $(wc -l < "$OUT" | tr -d ' ') secrets to: $OUT"
  say "Use with:  bash 04_purge_secrets.sh <clean-clone> --replace-file $OUT"
else
  err "No secrets entered - file left empty."
fi
