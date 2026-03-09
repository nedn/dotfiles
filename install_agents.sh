#!/usr/bin/env bash
# ============================================================
# AI Dev Tools Installer
# Installs: nvm, Node/npm, Claude Code, Codex CLI, Gemini CLI
# ============================================================

set -eo pipefail
set +x

NVM_VERSION="v0.40.4"
NODE_VERSION="24.0"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()    { echo -e "${GREEN}[✔]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
section() { echo -e "\n${YELLOW}──────────────────────────────────${NC}"; echo -e "  $1"; echo -e "${YELLOW}──────────────────────────────────${NC}"; }

# ── 1. Install nvm ───────────────────────────────────────────
section "Installing nvm ${NVM_VERSION}"

if [ -d "$HOME/.nvm" ]; then
  warn "nvm already installed at ~/.nvm — skipping download"
else
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
  info "nvm installed"
fi

# Load nvm into this session
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

# Ensure nvm is in shell config (idempotent)
SHELL_RC=""
if [ -f "$HOME/.zshrc" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -f "$HOME/.bashrc" ]; then
  SHELL_RC="$HOME/.bashrc"
fi

if [ -n "$SHELL_RC" ]; then
  NVM_INIT='[ -s "$HOME/.nvm/nvm.sh" ] && source "$HOME/.nvm/nvm.sh"'
  grep -qF 'nvm.sh' "$SHELL_RC" || echo -e "\n# nvm\nexport NVM_DIR=\"\$HOME/.nvm\"\n${NVM_INIT}" >> "$SHELL_RC"
fi

# ── 2. Install Node.js (LTS) + npm ───────────────────────────
section "Installing Node.js LTS + npm"

nvm install "$NODE_VERSION"
nvm use --lts "$NODE_VERSION"
nvm alias default "$NODE_VERSION"

info "Node $(node --version) / npm $(npm --version) active"

# ── 3. Install global AI CLI tools ───────────────────────────
section "Installing Claude Code"

# Native installer (recommended — replaces deprecated npm method)
curl -fsSL https://claude.ai/install.sh | bash

# Ensure the binary is on PATH (installer places it in ~/.local/bin)
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
  export PATH="$HOME/.local/bin:$PATH"
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
fi

info "claude installed → $(claude --version 2>/dev/null || echo 'run: claude')"

section "Installing OpenAI Codex CLI"
npm install -g @openai/codex
info "codex installed → $(codex --version 2>/dev/null || echo 'run: codex')"

section "Installing Gemini CLI"
npm install -g @google/gemini-cli
info "gemini installed → $(gemini --version 2>/dev/null || echo 'run: gemini')"

# ── Done ─────────────────────────────────────────────────────
echo -e "\n${GREEN}╔══════════════════════════════════╗${NC}"
echo -e "${GREEN}║   All tools installed! 🎉        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════╝${NC}"
echo ""
echo "  claude    → Claude Code (Anthropic)"
echo "  codex     → Codex CLI   (OpenAI)"
echo "  gemini    → Gemini CLI  (Google)"
echo ""
warn "Restart your terminal (or run: source ~/.bashrc / source ~/.zshrc)"
warn "Then authenticate each tool:"
echo "    claude    — runs setup on first launch"
echo "    codex     — set OPENAI_API_KEY env var"
echo "    gemini    — runs setup on first launch"
echo ""
