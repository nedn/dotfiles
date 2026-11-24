#!/usr/bin/env bash
# Bootstrap dotfiles with chezmoi (https://www.chezmoi.io/).
#
# Installs chezmoi into ~/.local/bin if missing, points it at this repo and
# applies the dotfiles. Re-running is safe. After the first run, use chezmoi
# directly: `chezmoi diff`, `chezmoi apply`, `chezmoi edit ~/.bashrc`, ...
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v chezmoi >/dev/null 2>&1; then
	if [ ! -x "$HOME/.local/bin/chezmoi" ]; then
		echo "Installing chezmoi into ~/.local/bin ..."
		sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
	fi
	export PATH="$HOME/.local/bin:$PATH"
fi

chezmoi init --source "$repo_dir" --apply "$@"
