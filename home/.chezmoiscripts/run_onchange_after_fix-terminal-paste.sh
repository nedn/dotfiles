#!/usr/bin/env bash
# Disable bracketed paste in readline and zsh (idempotent).
set -euo pipefail

if ! grep -q 'set enable-bracketed-paste off' ~/.inputrc 2>/dev/null; then
	echo 'set enable-bracketed-paste off' >> ~/.inputrc
	echo "Added bracketed paste fix to ~/.inputrc"
fi

case "$(uname -s)" in
	Darwin|Linux)
		if ! grep -q 'unset zle_bracketed_paste' ~/.zshrc 2>/dev/null; then
			echo "unset zle_bracketed_paste" >> ~/.zshrc
			echo "Added bracketed paste fix to ~/.zshrc"
		fi
		;;
esac
