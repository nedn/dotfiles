#!/usr/bin/env bash
# ============================================================
# Essential Tools Installer (Ubuntu/Debian)
# Installs: git, neovim, rsync, ripgrep
# ============================================================

set -eo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[✔]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
section() { echo -e "\n${YELLOW}──────────────────────────────────${NC}"; echo -e "  $1"; echo -e "${YELLOW}──────────────────────────────────${NC}"; }

TOOLS=(git neovim rsync ripgrep byobu)

# ── Update package index ─────────────────────────────────────
section "Updating apt package index"
if sudo apt-get update -y; then
  info "Package index updated"
else
  warn "Failed to update package index — continuing with existing index"
fi

# ── Install tools ────────────────────────────────────────────
for tool in "${TOOLS[@]}"; do
  section "Installing ${tool}"
  if dpkg -s "$tool" &>/dev/null; then
    warn "${tool} is already installed — skipping"
  else
    sudo apt-get install -y "$tool"
    info "${tool} installed"
  fi
done

# ── Install git-delta (from GitHub release) ─────────────────
section "Installing git-delta"
if command -v delta &>/dev/null; then
  warn "git-delta is already installed — skipping"
else
  DELTA_VERSION="$(curl -fSL -o /dev/null -w '%{url_effective}' https://github.com/dandavison/delta/releases/latest | grep -oP '[^/]+$')"
  DELTA_DEB="/tmp/git-delta.deb"
  curl -fSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/git-delta_${DELTA_VERSION}_amd64.deb" -o "$DELTA_DEB"
  sudo dpkg -i "$DELTA_DEB"
  rm -f "$DELTA_DEB"
  info "git-delta installed"
fi

# ── Done ─────────────────────────────────────────────────────
echo -e "\n${GREEN}╔══════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Essential tools installed! 🎉  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════╝${NC}"
echo ""
echo "  git     → $(git --version 2>/dev/null)"
echo "  nvim    → $(nvim --version 2>/dev/null | head -1)"
echo "  rsync   → $(rsync --version 2>/dev/null | head -1)"
echo "  rg      → $(rg --version 2>/dev/null | head -1)"
echo "  byobu   → $(byobu --version 2>/dev/null | head -1)"
echo "  delta   → $(delta --version 2>/dev/null | head -1)"
echo ""
