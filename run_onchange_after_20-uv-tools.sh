#!/bin/sh
# Installs Python CLI tools with uv. chezmoi reruns this when the file changes,
# so add a tool by adding it to the list below. Both installs are idempotent.
set -eu

uv="$HOME/.local/bin/uv"
if [ ! -x "$uv" ]; then
  curl -LsSf https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR="$HOME/.local/bin" UV_NO_MODIFY_PATH=1 sh
fi

for tool in graphifyy; do
  "$uv" tool install "$tool"
done

# graphify's Claude Code skill goes to ~/.claude/skills/graphify, plus a
# pointer in ~/.claude/CLAUDE.md. Neither is managed by this repo.
"$HOME/.local/bin/graphify" install --platform claude
