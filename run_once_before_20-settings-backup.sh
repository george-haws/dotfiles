#!/bin/sh
# Before chezmoi first writes the Claude Code and Zed settings on this machine,
# keep whatever is there. dotfiles-capture --from seeds the local files from
# these backups; see the README.
set -eu
for f in "$HOME/.claude/settings.json" "$HOME/.config/zed/settings.json"; do
  if [ -f "$f" ] && [ ! -e "$f.pre-chezmoi" ]; then
    cp -p "$f" "$f.pre-chezmoi"
    echo "Backed up $f to $f.pre-chezmoi"
  fi
done
