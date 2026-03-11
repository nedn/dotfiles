#!/usr/bin/env bash
# ============================================================
# Essential Tools Installer (Ubuntu/Debian)
# Installs: git, neovim, rsync
# ============================================================

set -eo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[✔]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
section() { echo -e "\n${YELLOW}──────────────────────────────────${NC}"; echo -e "  $1"; echo -e "${YELLOW}──────────────────────────────────${NC}"; }

TOOLS=(git neovim rsync)

# ── Update package index ─────────────────────────────────────
section "Updating apt package index"
sudo apt-get update -y
info "Package index updated"

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

# ── Done ─────────────────────────────────────────────────────
echo -e "\n${GREEN}╔══════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Essential tools installed! 🎉  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════╝${NC}"
echo ""
echo "  git     → $(git --version 2>/dev/null)"
echo "  nvim    → $(nvim --version 2>/dev/null | head -1)"
echo "  rsync   → $(rsync --version 2>/dev/null | head -1)"
echo ""
