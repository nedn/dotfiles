#!/usr/bin/env bash
set -euo pipefail

VERSION="0.18.2"
DEB_URL="https://github.com/dandavison/delta/releases/latest/download/git-delta_${VERSION}_amd64.deb"
TMP_DEB="/tmp/git-delta.deb"

if command -v delta &>/dev/null; then
  echo "git-delta is already installed: $(delta --version)"
  exit 0
fi

echo "Downloading git-delta v${VERSION}..."
curl -sL "$DEB_URL" -o "$TMP_DEB"

echo "Installing..."
sudo dpkg -i "$TMP_DEB"
rm -f "$TMP_DEB"

echo "Installed: $(delta --version)"
