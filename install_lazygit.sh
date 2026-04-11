#!/usr/bin/env bash

set -euo pipefail

REPO="jesseduffield/lazygit"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
FORCE=false
TMP_DIR=""

usage() {
  cat <<'EOF'
Usage: ./install_lazy_git.sh [--force] [--help]

Install the latest prebuilt lazygit binary for Linux from the upstream
GitHub releases:
https://github.com/jesseduffield/lazygit/releases/latest

Options:
  --force   Reinstall even if the latest version is already installed
  --help    Show this help text

Environment:
  INSTALL_DIR  Destination directory for the lazygit binary
               (default: /usr/local/bin)
EOF
}

info() {
  printf '[*] %s\n' "$1"
}

warn() {
  printf '[!] %s\n' "$1"
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

run_install() {
  local destination_dir="${1}"
  shift

  if [[ -d "$destination_dir" && -w "$destination_dir" ]]; then
    install "$@"
    return
  fi

  if [[ ! -d "$destination_dir" && -w "$(dirname "$destination_dir")" ]]; then
    install "$@"
    return
  fi

  if [[ $EUID -eq 0 ]]; then
    install "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo install "$@"
    return
  fi

  die "installing into ${destination_dir} requires root or sudo"
}

for arg in "$@"; do
  case "$arg" in
    --force)
      FORCE=true
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $arg"
      ;;
  esac
done

trap cleanup EXIT

if [[ "$(uname -s)" != "Linux" ]]; then
  die "this installer currently supports Linux only"
fi

if ! command -v curl >/dev/null 2>&1; then
  die "curl is required"
fi

if ! command -v tar >/dev/null 2>&1; then
  die "tar is required"
fi

case "$(uname -m)" in
  x86_64|amd64)
    asset_arch="x86_64"
    ;;
  aarch64|arm64)
    asset_arch="arm64"
    ;;
  armv7l|armv6l)
    asset_arch="armv6"
    ;;
  *)
    die "unsupported CPU architecture: $(uname -m)"
    ;;
esac

latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
latest_tag="${latest_url##*/}"
latest_version="${latest_tag#v}"
archive_name="lazygit_${latest_version}_Linux_${asset_arch}.tar.gz"
download_url="https://github.com/${REPO}/releases/download/${latest_tag}/${archive_name}"

if command -v lazygit >/dev/null 2>&1; then
  installed_version="$(lazygit --version 2>/dev/null | grep -oE 'version=[^,]+' | head -n1 | cut -d= -f2 | tr -d '"' || true)"
  if [[ "$installed_version" == "$latest_version" && "$FORCE" != true ]]; then
    info "lazygit ${latest_version} is already installed at $(command -v lazygit)"
    exit 0
  fi
fi

TMP_DIR="$(mktemp -d)"
archive_path="${TMP_DIR}/${archive_name}"

info "Downloading lazygit ${latest_version} for Linux/${asset_arch}"
curl -fL "$download_url" -o "$archive_path"

info "Extracting ${archive_name}"
tar -xzf "$archive_path" -C "$TMP_DIR"

lazygit_path="$(find "$TMP_DIR" -type f -name lazygit -print -quit)"
if [[ -z "$lazygit_path" ]]; then
  die "downloaded archive did not contain a lazygit binary"
fi

info "Installing lazygit to ${INSTALL_DIR}"
run_install "$INSTALL_DIR" -d "$INSTALL_DIR"
run_install "$INSTALL_DIR" -m 0755 "$lazygit_path" "${INSTALL_DIR}/lazygit"

info "Installed $( "${INSTALL_DIR}/lazygit" --version | head -n1 )"
