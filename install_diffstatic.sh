#!/usr/bin/env bash

set -euo pipefail

REPO="Wilfred/difftastic"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
FORCE=false
TMP_DIR=""

usage() {
  cat <<'EOF'
Usage: ./install_diffstatic.sh [--force] [--help]

Install the latest prebuilt difftastic binary for Linux by following the
official release-based installation flow from:
https://difftastic.wilfred.me.uk/installation.html

Options:
  --force   Reinstall even if the latest version is already installed
  --help    Show this help text

Environment:
  INSTALL_DIR  Destination directory for the difft binary
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
    asset_arch="aarch64"
    ;;
  *)
    die "unsupported CPU architecture: $(uname -m)"
    ;;
esac

asset_target="unknown-linux-gnu"
if command -v ldd >/dev/null 2>&1 && ldd --version 2>&1 | grep -qi musl; then
  if [[ "$asset_arch" == "x86_64" ]]; then
    asset_target="unknown-linux-musl"
  else
    die "upstream releases do not currently provide an aarch64 musl Linux binary"
  fi
fi

latest_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest")"
latest_version="${latest_url##*/}"
archive_name="difft-${asset_arch}-${asset_target}.tar.gz"
download_url="https://github.com/${REPO}/releases/download/${latest_version}/${archive_name}"

if command -v difft >/dev/null 2>&1; then
  installed_version="$(difft --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){1,2}' | head -n1 || true)"
  if [[ "$installed_version" == "$latest_version" && "$FORCE" != true ]]; then
    info "difftastic ${latest_version} is already installed at $(command -v difft)"
    exit 0
  fi
fi

TMP_DIR="$(mktemp -d)"
archive_path="${TMP_DIR}/${archive_name}"

info "Downloading difftastic ${latest_version} for ${asset_arch}/${asset_target}"
curl -fL "$download_url" -o "$archive_path"

info "Extracting ${archive_name}"
tar -xzf "$archive_path" -C "$TMP_DIR"

difft_path="$(find "$TMP_DIR" -type f -name difft -print -quit)"
if [[ -z "$difft_path" ]]; then
  die "downloaded archive did not contain a difft binary"
fi

info "Installing difft to ${INSTALL_DIR}"
run_install "$INSTALL_DIR" -d "$INSTALL_DIR"
run_install "$INSTALL_DIR" -m 0755 "$difft_path" "${INSTALL_DIR}/difft"

info "Installed $( "${INSTALL_DIR}/difft" --version | head -n1 )"
