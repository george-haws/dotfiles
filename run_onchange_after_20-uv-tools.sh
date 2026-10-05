#!/bin/sh
# Installs Python CLI tools with uv. chezmoi reruns this when the file changes,
# so add a tool by adding it to the list below. Both installs are idempotent.
set -eu

# uv comes from the Brewfile, which the homebrew script installs first.
uv=/opt/homebrew/bin/uv

for tool in graphifyy; do
  "$uv" tool install "$tool"
done

# graphify's Claude Code skill goes to ~/.claude/skills/graphify, plus a
# pointer in ~/.claude/CLAUDE.md. Neither is managed by this repo.
"$HOME/.local/bin/graphify" install --platform claude
