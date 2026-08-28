#!/usr/bin/env bash
# =============================================================================
# 00_preflight.sh  -  Install/verify ALL prerequisites for the secrets cleanup.
#
# Run ONCE per machine, BEFORE anything else:
#     bash 00_preflight.sh
#
# Installs: gitleaks, trufflehog, git-filter-repo, git-delta (optional), bfg (optional)
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[0;33m'; RED='\033[0;31m'; NC='\033[0m'
say()  { printf "${GREEN}[preflight]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[preflight]${NC} %s\n" "$*"; }
fail() { printf "${RED}[preflight]${NC} %s\n" "$*"; exit 1; }

# --- Detect package managers / OS -------------------------------------------
OS="$(uname -s)"
HAS_BREW=$(command -v brew || true)
HAS_APT=$(command -v apt-get || true)
HAS_DNF=$(command -v dnf || true)
HAS_PIP=$(command -v pip3 || true)
ARCH="$(uname -m)"

# --- 1. git (required) ------------------------------------------------------
command -v git >/dev/null || fail "git is not installed. Install git first."
say "git detected: $(git --version)"

# --- 2. gitleaks ------------------------------------------------------------
if ! command -v gitleaks >/dev/null 2>&1; then
  say "Installing gitleaks..."
  if [ -n "$HAS_BREW" ]; then
    brew install gitleaks
  elif command -v go >/dev/null 2>&1; then
    go install github.com/gitleaks/gitleaks/v8@latest
    sudo install "$(go env GOPATH)/bin/gitleaks" /usr/local/bin/gitleaks || true
  else
    # Grab the latest release binary from GitHub
    GL_URL="https://github.com/gitleaks/gitleaks/releases/latest/download/gitleaks_${OS,,}_${ARCH}.tar.gz"
    warn "Downloading gitleaks from: $GL_URL"
    tmp=$(mktemp -d)
    curl -sSfL "$GL_URL" | tar -xz -C "$tmp"
    sudo install "$tmp/gitleaks" /usr/local/bin/gitleaks
    rm -rf "$tmp"
  fi
else
  say "gitleaks already installed: $(gitleaks version 2>/dev/null | head -1)"
fi

# --- 3. trufflehog ----------------------------------------------------------
if ! command -v trufflehog >/dev/null 2>&1; then
  say "Installing trufflehog..."
  if [ -n "$HAS_BREW" ]; then
    brew install trufflehog
  elif command -v go >/dev/null 2>&1; then
    go install github.com/trufflesecurity/trufflehog/v3@latest
    sudo install "$(go env GOPATH)/bin/trufflehog" /usr/local/bin/trufflehog || true
  else
    TH_URL="https://github.com/trufflesecurity/trufflehog/releases/latest/download/trufflehog_${OS}_${ARCH}.tar.gz"
    warn "Downloading trufflehog from: $TH_URL"
    tmp=$(mktemp -d)
    curl -sSfL "$TH_URL" | tar -xz -C "$tmp"
    sudo install "$tmp/trufflehog" /usr/local/bin/trufflehog
    rm -rf "$tmp"
  fi
else
  say "trufflehog already installed: $(trufflehog --version 2>/dev/null | head -1)"
fi

# --- 4. git-filter-repo (required for history rewrite) -----------------------
if ! command -v git-filter-repo >/dev/null 2>&1 && ! git filter-repo --help >/dev/null 2>&1; then
  say "Installing git-filter-repo..."
  if [ -n "$HAS_BREW" ]; then
    brew install git-filter-repo
  elif [ -n "$HAS_APT" ]; then
    sudo apt-get install -y git-filter-repo
  elif [ -n "$HAS_DNF" ]; then
    sudo dnf install -y git-filter-repo
  elif [ -n "$HAS_PIP" ]; then
    pip3 install --user git-filter-repo
  else
    warn "Downloading git-filter-repo (single script) to /usr/local/bin..."
    sudo curl -sSfL https://raw.githubusercontent.com/newren/git-filter-repo/main/git-filter-repo -o /usr/local/bin/git-filter-repo
    sudo chmod +x /usr/local/bin/git-filter-repo
  fi
else
  say "git-filter-repo already available."
fi

# --- 5. bfg (optional, fallback for very large repos) ------------------------
if ! command -v bfg >/dev/null 2>&1; then
  warn "bfg is optional (fast fallback for huge repos). Skipping auto-install (needs Java)."
else
  say "bfg already installed."
fi

# --- 6. Optional niceties ----------------------------------------------------
command -v jq  >/dev/null 2>&1 && say "jq present"          || warn "jq not found (nice for JSON, not required)"
command -v ripgrep >/dev/null 2>&1 && say "rg present"      || warn "ripgrep not found (fallback to grep works)"

# --- Final verification ------------------------------------------------------
echo ""
say "=== Final check ==="
for tool in git gitleaks trufflehog; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf "  ${GREEN}OK ${NC} %-14s %s\n" "$tool" "$(command -v $tool)"
  else
    printf "  ${RED}MISSING ${NC} %s\n" "$tool"
  fi
done
if git filter-repo --help >/dev/null 2>&1 || command -v git-filter-repo >/dev/null 2>&1; then
  printf "  ${GREEN}OK ${NC} %-14s git-filter-repo\n" "git-filter-repo"
else
  printf "  ${RED}MISSING ${NC} %s\n" "git-filter-repo"
fi

echo ""
say "Preflight complete. If anything shows MISSING above, fix it before continuing."
say "Next step: read 01_intro.sh / README.md, then run 02_scan_repos.sh"
