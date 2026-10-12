#!/bin/bash
# PostToolUse hook. When a Write, Edit, or Bash call writes a superpowers spec
# or plan (docs/superpowers/specs/*.md or docs/superpowers/plans/*.md), remind
# the writer to run the cross-model-review skill before handing the document to
# George. Anything else, including malformed input, exits 0 with no output so a
# hook problem can never block a tool call.
#
# Inside a subagent (the input carries a non-empty agent_id), the writer cannot
# triage findings with George, so the context instead tells it to leave the
# review alone and report the change to its caller, which runs the review.
#
# Bash matching is a string match on the command text, not a file event. A path
# counts only when it follows a redirect, is an argument to tee, or the command
# is an in-place sed/perl edit that mentions the path. Reads never count. Known
# false positives, accepted: a redirect inside a string literal, and an in-place
# edit of another file in a command that also reads the spec.

input=$(cat) || exit 0
[ -n "$input" ] || exit 0
tool=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null) || exit 0

# A spec or plan path, with any non-space prefix (absolute paths) and no quotes.
# The .md must end the token (whitespace, a quote, a shell separator, or end of
# string), so x.md.backup does not count; the Write/Edit branch appends a space
# to the path so the same pattern applies.
RE_PATH="[^[:space:]\"']*docs/superpowers/(specs|plans)/[^[:space:]\"']+[.]md([[:space:]\"';&|()<>]|$)"
Q="[\"']?"
RE_REDIRECT=">>?[[:space:]]*${Q}${RE_PATH}"
RE_TEE="(^|[[:space:]|;&])tee([[:space:]]+-[a-zA-Z]+)*[[:space:]]+${Q}${RE_PATH}"
RE_INPLACE="(^|[[:space:]|;&(])(sed|perl)[[:space:]]+-[a-zA-Z]*i"

hit=0
case "$tool" in
  Write|Edit)
    path=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null) || exit 0
    [[ "$path " =~ ^${RE_PATH} ]] && hit=1
    ;;
  Bash)
    cmd=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null) || exit 0
    if [[ $cmd =~ $RE_REDIRECT ]] || [[ $cmd =~ $RE_TEE ]]; then
      hit=1
    elif [[ $cmd =~ $RE_INPLACE ]] && [[ $cmd =~ $RE_PATH ]]; then
      hit=1
    fi
    ;;
esac
[ "$hit" = 1 ] || exit 0
agent=$(jq -r '.agent_id // empty' <<<"$input" 2>/dev/null) || exit 0

if [ -n "$agent" ]; then
read -r -d '' NUDGE <<'EOF'
This file is a superpowers spec or plan, and you are running as a subagent. Do not run the cross-model review yourself. When you report back, tell your caller that you changed this spec or plan so it can run the `cross-model-review` skill before the document goes to George.
EOF
else
read -r -d '' NUDGE <<'EOF'
This file is a superpowers spec or plan. Before you hand it to George for review, run the `cross-model-review` skill on it. Sequence: finish the superpowers self-review and every fix that comes out of it first, then run the cross-model review on the final draft, immediately before the user review gate. A review counts only if the document has not changed since it ran. The one exception is edits that come out of George's triage of the findings; those are his decisions and do not need a second review.
EOF
fi

jq -n -c --arg ctx "$NUDGE" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0
