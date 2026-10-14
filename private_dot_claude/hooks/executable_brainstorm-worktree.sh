#!/bin/bash
# UserPromptSubmit and PostToolUse hook. When a superpowers brainstorming
# session starts, tell Claude to move the session into a new worktree based on
# the latest default branch before doing anything else. Two starts count: George
# typing /superpowers:brainstorming (UserPromptSubmit) and Claude invoking the
# skill through the Skill tool (PostToolUse). Anything else, including malformed
# input, exits 0 with no output so a hook problem can never block a prompt or
# tool call.
#
# Stays silent outside a git repository and inside a linked worktree: the
# session is already isolated there, so it keeps working in place. The worktree
# itself comes from EnterWorktree, which branches from origin/<default-branch>
# (worktree.baseRef "fresh"); this hook fetches origin first so that ref is
# current.

input=$(cat) || exit 0
[ -n "$input" ] || exit 0
event=$(jq -r '.hook_event_name // empty' <<<"$input" 2>/dev/null) || exit 0

case "$event" in
  UserPromptSubmit)
    prompt=$(jq -r '.prompt // empty' <<<"$input" 2>/dev/null) || exit 0
    [[ $prompt =~ ^[[:space:]]*/superpowers:brainstorming([[:space:]]|$) ]] || exit 0
    ;;
  PostToolUse)
    skill=$(jq -r '.tool_input.skill // empty' <<<"$input" 2>/dev/null) || exit 0
    [ "$skill" = "superpowers:brainstorming" ] || exit 0
    ;;
  *) exit 0 ;;
esac

cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null) || exit 0
[ -n "$cwd" ] || cwd=$PWD
git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0
git_dir=$(cd "$cwd" && cd "$(git rev-parse --git-dir 2>/dev/null)" 2>/dev/null && pwd -P) || exit 0
git_common=$(cd "$cwd" && cd "$(git rev-parse --git-common-dir 2>/dev/null)" 2>/dev/null && pwd -P) || exit 0
# A linked worktree has its own git dir. Submodules do too, so rule them out.
if [ "$git_dir" != "$git_common" ] && [ -z "$(git -C "$cwd" rev-parse --show-superproject-working-tree 2>/dev/null)" ]; then
  exit 0
fi

if git -C "$cwd" fetch --quiet origin >/dev/null 2>&1; then
  stale=""
else
  stale=" Fetching origin failed, so the worktree may start from a stale origin/<default-branch>; tell George that when you report the worktree."
fi

read -r -d '' NUDGE <<EOF
A superpowers brainstorming session is starting. Before anything else in it, including exploring project context or asking questions, call the EnterWorktree tool with a short kebab-case name for the topic. EnterWorktree branches from the latest origin/<default-branch>. All work for this brainstorm, including specs, plans, and implementation, happens in that worktree. Tell George the worktree path and branch once you are in it.${stale}
EOF

jq -n -c --arg ev "$event" --arg ctx "$NUDGE" \
  '{hookSpecificOutput:{hookEventName:$ev,additionalContext:$ctx}}'
exit 0
