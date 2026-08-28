#!/usr/bin/env bash
# =============================================================================
# helpers/list_repos.sh  -  Interactive repository picker.
#
# Lets you choose which repo(s) to scan. Writes the selection to
# ./repos.txt so other scripts (scan) can reuse the same list.
# =============================================================================
set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
say()  { printf "${GREEN}[list]${NC} %s\n" "$*"; }
err()  { printf "${RED}[list]${NC} %s\n" "$*"; }

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LISTFILE="$ROOT/repos.txt"
: > "$LISTFILE"

echo "Add the FULL PATH of each git repo you want to clean."
echo "(Press <blank> ENTER to stop adding. Type 'done' when finished.)"
while true; do
  read -rp "  Repo path> " p
  [ -z "$p" ] && break
  [ "$p" = "done" ] && break
  if [ -d "$p/.git" ] || [ -f "$p/HEAD" ]; then
    echo "$(cd "$p" && pwd)" >> "$LISTFILE"
    say "Added: $p"
  else
    err "'$p' is not a git repo - skipped."
  fi
done

if [ -s "$LISTFILE" ]; then
  say "Saved $(wc -l < "$LISTFILE" | tr -d ' ') repo(s) to: $LISTFILE"
  cat "$LISTFILE" | sed 's/^/   - /'
else
  err "No repos added."
fi
