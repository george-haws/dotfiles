#!/bin/sh
# Fresh-machine bootstrap. Run as:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/george-haws/dotfiles/master/install.sh)"
# The sh -c "$(...)" form keeps stdin on the terminal so chezmoi can prompt.
set -eu

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Installing the Xcode Command Line Tools. Re-run this script when the installer finishes."
  xcode-select --install
  exit 1
fi

mkdir -p "$HOME/.local/bin"
if [ ! -x "$HOME/.local/bin/chezmoi" ]; then
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
fi

exec "$HOME/.local/bin/chezmoi" init --source "$HOME/.dotfiles" --apply --guess-repo-url=false https://github.com/george-haws/dotfiles.git
