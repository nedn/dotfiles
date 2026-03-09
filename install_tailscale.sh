#!/bin/bash

set -e

# ─────────────────────────────────────────
# Tailscale Installer
# Usage: ./install-tailscale.sh [--ssh]
# ─────────────────────────────────────────

ENABLE_SSH=false

for arg in "$@"; do
  case $arg in
    --ssh)
      ENABLE_SSH=true
      ;;
    --help|-h)
      echo "Usage: $0 [--ssh]"
      echo ""
      echo "Options:"
      echo "  --ssh    Enable Tailscale SSH on this machine"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Usage: $0 [--ssh]"
      exit 1
      ;;
  esac
done

# ── Check for root ──────────────────────
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root (use sudo)."
  exit 1
fi

# ── Install Tailscale ───────────────────
echo "→ Installing Tailscale..."

# Download and run the official installer, but allow apt-get update to
# continue even if unrelated third-party repos fail (e.g. a 401 from a
# GCP Artifact Registry / Helm repo that has nothing to do with Tailscale).
curl -fsSL https://tailscale.com/install.sh \
  | sed 's/apt-get update$/apt-get update || true/g' \
  | sh

# ── Enable & start the service ──────────
echo "→ Enabling tailscaled service..."
systemctl enable --now tailscaled

# ── Build tailscale up arguments ────────
UP_ARGS=""

if [[ "$ENABLE_SSH" == true ]]; then
  echo "→ SSH support enabled."
  UP_ARGS="$UP_ARGS --ssh"
fi

# ── Bring up Tailscale ──────────────────
echo "→ Bringing up Tailscale..."
tailscale up $UP_ARGS

echo ""
echo "✓ Tailscale is up!"
tailscale ip -4 2>/dev/null && echo "(IPv4 address shown above)" || true

if [[ "$ENABLE_SSH" == true ]]; then
  echo ""
  echo "✓ Tailscale SSH is enabled."
  echo "  You can now SSH into this machine via its Tailscale hostname or IP."
  echo "  Example: ssh $(hostname)"
fi
