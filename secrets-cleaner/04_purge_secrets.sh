#!/usr/bin/env bash
# =============================================================================
# 04_purge_secrets.sh  -  REWRITE history to strip secrets from EVERY commit.
#
# Operates on the prepared CLEAN clone (from step 03). Uses git-filter-repo
# (the modern, recommended replacement for filter-branch).
#
# Purge strategies:
#   a) --strip-file <path>       remove an entire file (e.g. config/secrets.env)
#   b) --strip-glob '<glob>'     remove files matching a glob (e.g. '*.env')
#   c) --replace-value <secret>  replace an exact secret string everywhere
#   d) --replace-file <file>     use a "secret==>replacement" replacements file
#                                (great for a whole list of secrets at once)
#
# Usage examples:
#   bash 04_purge_secrets.sh ${SAFE} --strip-file config/secrets.env
#   bash 04_purge_secrets.sh ${SAFE} --strip-glob '*.env'
#   bash 04_purge_secrets.sh ${SAFE} --replace-file backups/secrets.txt
#   bash 04_purge_secrets.sh ${SAFE} --replace-value 'AKIAIOSFODNN7EXAMPLE'
#
#   Multiple flags can be combined in one call. Run it ONCE per repo after
#   listing every secret. Re-run is fine but each pass rewrites history again.
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
say()  { printf "${GREEN}[purge]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[purge]${NC} %s\n" "$*"; }
err()  { printf "${RED}[purge]${NC} %s\n" "$*" >&2; }

REPO="${1:?Usage: bash 04_purge_secrets.sh <clean-clone-path> [--strip-file X] [--strip-glob Y] [--replace-value Z] [--replace-file F]}"
shift
[ -d "$REPO" ] || { err "'$REPO' is not a directory."; exit 1; }
[ -d "$REPO/objects" ] || { err "'$REPO' does not look like a git repository. Run 03_prepare_repo.sh first."; exit 1; }

# git-filter-repo availability check
if ! git filter-repo --version >/dev/null 2>&1 && ! command -v git-filter-repo >/dev/null 2>&1; then
  err "git-filter-repo not found. Run:  bash 00_preflight.sh"
  exit 1
fi

# --- collect filters ----------------------------------------------------------
FILTER_ARGS=()      # args passed directly to git-filter-repo
PATH_STRIPS=()      # --path / --path-glob selections (removed via --invert-paths)
HAD_REPLACE=false
NEED_CONFIRM=true

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --strip-file)
        PATH_STRIPS+=(--path "$2"); shift 2 ;;
      --strip-glob)
        PATH_STRIPS+=(--path-glob "$2"); shift 2 ;;
      --replace-value)
        # Build a real replacements file (literal mode) so no process-substitution
        # fragility; stores the secret in a temp file that is deleted afterwards.
        local secret="$2"; shift 2
        local rf
        rf="$(mktemp "${TMPDIR:-/tmp}/secrets_XXXXXX.txt")"
        printf '%s==>REDACTED\n' "$secret" >> "$rf"
        REPLACE_FILES+=("$rf")
        HAD_REPLACE=true
        ;;
      --replace-file)
        local rf="$2"; shift 2
        [ -s "$rf" ] || { err "replacements file '$rf' missing/empty."; exit 1; }
        REPLACE_FILES+=("$rf")
        HAD_REPLACE=true
        ;;
      --yes)
        NEED_CONFIRM=false; shift ;;
      *)
        err "Unknown argument: $1"; exit 1 ;;
    esac
  done
}
REPLACE_FILES=()
parse_args "$@"

# If any path-strip was requested, the ENTIRE selection must be inverted so we
# keep everything EXCEPT the listed paths. This is git-filter-repo semantics.
if [ "${#PATH_STRIPS[@]}" -gt 0 ]; then
  FILTER_ARGS+=("${PATH_STRIPS[@]}" --invert-paths)
fi
# Forward every replace-text file as a --replace-text option.
for rf in "${REPLACE_FILES[@]}"; do
  FILTER_ARGS+=(--replace-text "$rf")
done

[ "${#FILTER_ARGS[@]}" -gt 0 ] || {
  err "No purge strategy given. Add at least one of --strip-file / --strip-glob /"
  err "  --replace-value / --replace-file. See header for examples."
  exit 1
}

echo ""
printf "${CYAN}Repo to rewrite: %s${NC}\n" "$REPO"
printf "${CYAN}Filters: %s${NC}\n" "${FILTER_ARGS[*]}"
echo "  This will REWRITE EVERY COMMIT. A backup was made in step 03 (backups/)."

if $NEED_CONFIRM; then
  warn "Have you ROTATED the secrets at their source first? (History rewrite != fix.)"
  read -rp "Type YES to proceed: " ans
  [[ "$ans" == "YES" ]] || { err "Aborted (did not type YES)."; exit 1; }
fi

# --- run filter-repo ----------------------------------------------------------
say "Rewriting history with git-filter-repo ..."
git -C "$REPO" filter-repo --force "${FILTER_ARGS[@]}" </dev/null
rc=$?
# Always delete any temp replacements files (they contain raw secrets).
for rf in "${REPLACE_FILES[@]}"; do
  case "$rf" in /tmp/*|"${TMPDIR:-/tmp}"/*) rm -f "$rf" ;; esac
done
[ "$rc" -eq 0 ] || { err "git-filter-repo failed (exit $rc)."; exit $rc; }
say "filter-repo finished."

# --- cleanup: remove dangling refs / reflog / objects -------------------------
say "Expiring reflogs and pruning unreachable objects..."
git -C "$REPO" for-each-ref --format='delete %(refname)' refs/original refs/filter >/dev/null 2>&1 | \
    git -C "$REPO" update-ref --stdin || true
git -C "$REPO" reflog expire --expire=now --all
git -C "$REPO" gc --prune=now --aggressive

# git-filter-repo removes the 'origin' remote by design; re-add it from the
# original repo's remote so step 06 can push. Skip if we can find origin URL.
ORIGIN=$(git -C "$REPO" remote get-url origin 2>/dev/null || true)
if [ -z "$ORIGIN" ]; then
  warn "filter-repo removed the 'origin' remote. Re-add it before step 06:"
  printf "  git -C %s remote add origin <your-github-url>\n" "$REPO"
fi

say "Done. History rewritten and pruned."
say "Next: verify with  bash 05_verify_clean.sh $REPO"
