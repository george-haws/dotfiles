# Cross-Model Spec Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every superpowers spec or plan gets reviewed by a fresh, read-only agent on a different model before George reads it, and George triages the findings one at a time.

**Architecture:** A PostToolUse hook in the chezmoi-managed dotfiles detects writes to `docs/superpowers/specs/` or `plans/` and injects a reminder. The writer then runs a hand-managed `cross-model-review` skill, which hashes the document, dispatches a hand-managed read-only `cross-model-reviewer` agent on the other model, validates the return, and walks George through findings. The dotfiles doctor checks that the two hand-managed files exist, since chezmoi deploys the hook but not them.

**Tech Stack:** bash 3.2 (macOS), `jq` (at `/usr/bin/jq`), chezmoi, POSIX sh for the doctor and tests, Claude Code hooks, skills, and agent definitions.

**Spec:** `docs/superpowers/specs/2026-10-11-cross-model-spec-review-design.md`

## Global Constraints

- The hook must never block or fail a tool call: exit 0 with no output on anything it does not recognise, including malformed JSON.
- Hook output on a match is exactly `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"<nudge text>"}}`.
- Bash matching counts a path only after a redirect (`>` or `>>`), as a `tee` argument, or in an in-place `sed -i` or `perl -i` edit. Reads (`cat`, `grep`, `git diff`, `shasum`) never count. The `.md` must end the path token. Two false positives are accepted and tested as such: a redirect inside a string literal, and an in-place edit of another file in a command that also reads the spec.
- The reviewer agent has tools `Read, Grep, Glob` only and no model of its own.
- Reviewer model: writer Fable → `opus`; writer Opus → `fable`; anything else → `fable`.
- Model comparison is by family (fable vs opus), not by string.
- Findings are triaged one at a time, with a running tally line, and are never applied without George's choice.
- The skill and agent live in `~/.claude/skills/cross-model-review/SKILL.md` and `~/.claude/agents/cross-model-reviewer.md`, outside chezmoi.
- Repo tests run with `./test/render.sh` from `~/.dotfiles` and must end with `all checks passed`.
- Commit messages are a short imperative sentence, no prefix, and end with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.

---

## File Structure

| File | Task | Responsibility |
|------|------|----------------|
| `private_dot_claude/hooks/executable_spec-review-nudge.sh` | 1 | Read a PostToolUse payload, decide whether it wrote a spec or plan, print the nudge JSON |
| `test/render.sh` | 1, 2, 3 | Assertions on the rendered hook, the settings entry, and the doctor source |
| `.shared/claude-settings.json` | 2 | Register the hook under `hooks.PostToolUse` |
| `README.md` | 2 | Document the hook and the two hand-managed files |
| `dot_local/bin/executable_dotfiles-doctor.tmpl` | 3 | Fail when the skill or agent file is missing, or the hook is not wired |
| `~/.claude/agents/cross-model-reviewer.md` | 4 | Read-only reviewer: tools and the review brief |
| `~/.claude/skills/cross-model-review/SKILL.md` | 5 | Model choice, hashing, dispatch, validation, triage, editing pass |

Tasks 1 to 3 are in the `~/.dotfiles` repo. Tasks 4 and 5 are hand-managed files with no repo. Task 6 is live verification.

---

### Task 1: The nudge hook script

**Files:**
- Create: `private_dot_claude/hooks/executable_spec-review-nudge.sh`
- Modify: `test/render.sh` (the assertion at the line reading `check_eq "claude settings($t): settings.json and statusline.sh under .claude"`, currently line 355, and a new section appended at the end before any trailing `finish`)

**Interfaces:**
- Consumes: a PostToolUse payload on stdin with `tool_name` and `tool_input` (`file_path` for Write and Edit, `command` for Bash).
- Produces: the rendered script at `~/.claude/hooks/spec-review-nudge.sh`, referenced by Task 2's settings entry and Task 3's doctor check. The nudge text names the skill `cross-model-review`, which Task 5 creates.

- [ ] **Step 1: Fix the existing file-list assertion so it expects the hook**

In `test/render.sh`, find:

```sh
  check_eq "claude settings($t): settings.json and statusline.sh under .claude" "$(find "$tmp/$t/.claude" -type f | sed "s|$tmp/$t/.claude/||" | sort | tr '\n' ' ')" "settings.json statusline.sh "
```

Replace with:

```sh
  check_eq "claude settings($t): hook, settings.json and statusline.sh under .claude" "$(find "$tmp/$t/.claude" -type f | sed "s|$tmp/$t/.claude/||" | sort | tr '\n' ' ')" "hooks/spec-review-nudge.sh settings.json statusline.sh "
```

- [ ] **Step 2: Append the hook assertions to `test/render.sh`**

Add this block at the end of the assertions, before the final `finish` call:

```sh
# Task 1 (2026-10-11): cross-model review nudge hook
hk="$P/.claude/hooks/spec-review-nudge.sh"
[ -x "$hk" ] && pass "nudge hook: executable" || fail "nudge hook: not executable"
bash -n "$hk" && pass "nudge hook: bash -n" || fail "nudge hook: syntax"
: > "$tmp/hk.err"
# Payloads are built from jq arguments, never from a JSON literal: bash 3.2
# brace-expands {"a":..,"b":..} inside nested "$(...)" quoting.
# Each helper leaves the hook's exit status in $rc: the hook is the last
# command in the pipeline, so $? after the capture is its status.
nudge() { # tool-name input-key input-value -> hook stdout, $rc
  out=$(jq -c -n --arg t "$1" --arg k "$2" --arg v "$3" '{tool_name:$t, tool_input:{($k):$v}}' | bash "$hk" 2>>"$tmp/hk.err"); rc=$?
  printf '%s' "$out"
}
nudge_raw() { # raw-stdin -> hook stdout, $rc
  out=$(printf '%s' "$1" | bash "$hk" 2>>"$tmp/hk.err"); rc=$?
  printf '%s' "$out"
}
is_nudge() { # desc output
  if [ -z "$2" ]; then fail "$1: no output"; return; fi
  check_eq "$1: event name" "$(printf '%s' "$2" | jq -r '.hookSpecificOutput.hookEventName')" "PostToolUse"
  check_eq "$1: only hookSpecificOutput at top level" "$(printf '%s' "$2" | jq -c 'keys')" '["hookSpecificOutput"]'
  check_eq "$1: only the two keys inside" "$(printf '%s' "$2" | jq -c '.hookSpecificOutput | keys')" '["additionalContext","hookEventName"]'
  ctx=$(printf '%s' "$2" | jq -r '.hookSpecificOutput.additionalContext')
  case "$ctx" in "This file is a superpowers spec or plan."*) pass "$1: context opens with the sentence";; *) fail "$1: context opens '$ctx'";; esac
  for phrase in 'cross-model-review' 'self-review' 'final draft' 'has not changed' 'triage'; do
    case "$ctx" in *"$phrase"*) pass "$1: context mentions $phrase";; *) fail "$1: context lacks '$phrase'";; esac
  done
}
yes_nudge() { out=$(nudge "$2" "$3" "$4"; echo "rc=$rc"); rc=${out##*rc=}; out=${out%rc=*}; is_nudge "$1" "$out"; check_eq "$1: exit 0" "$rc" "0"; }   # desc tool key value
no_nudge()  { out=$(nudge "$2" "$3" "$4"; echo "rc=$rc"); rc=${out##*rc=}; out=${out%rc=*}; check_eq "$1: no output" "$out" ""; check_eq "$1: exit 0" "$rc" "0"; }
raw_silent() { out=$(nudge_raw "$2"; echo "rc=$rc"); rc=${out##*rc=}; out=${out%rc=*}; check_eq "$1: no output" "$out" ""; check_eq "$1: exit 0" "$rc" "0"; }   # desc raw-stdin
S='docs/superpowers/specs/2026-01-01-x-design.md'
PL='docs/superpowers/plans/2026-01-01-x.md'
yes_nudge "Write spec" Write file_path "$S"
yes_nudge "Write plan" Write file_path "$PL"
yes_nudge "Write spec, absolute path outside cwd" Write file_path "/Users/someone/elsewhere/$S"
yes_nudge "Edit spec" Edit file_path "$S"
yes_nudge "Bash heredoc to spec" Bash command "cat > $S <<'EOF'
hello
EOF"
yes_nudge "Bash append redirect to plan" Bash command "echo more >> $PL"
yes_nudge "Bash redirect with quoted path" Bash command "printf x > \"$S\""
yes_nudge "Bash tee to spec" Bash command "echo x | tee $S"
yes_nudge "Bash tee -a to spec" Bash command "echo x | tee -a $S"
yes_nudge "Bash sed -i on spec" Bash command "sed -i '' 's/a/b/' $S"
yes_nudge "Bash sed -i via variable" Bash command "f=$S && sed -i '' 's/a/b/' \"\$f\""
yes_nudge "Bash perl -pi on plan" Bash command "perl -pi -e 's/a/b/' $PL"
no_nudge "Write markdown elsewhere" Write file_path "docs/notes/x.md"
no_nudge "Write non-markdown in specs dir" Write file_path "docs/superpowers/specs/x.txt"
no_nudge "Read tool on spec" Read file_path "$S"
no_nudge "Bash cat spec" Bash command "cat $S"
no_nudge "Bash grep spec" Bash command "grep -n requirement $S"
no_nudge "Bash git diff spec" Bash command "git diff -- $S"
no_nudge "Bash shasum spec" Bash command "shasum -a 256 $S"
no_nudge "Bash redirect spec into another file" Bash command "cat $S > /tmp/copy.md"
no_nudge "Bash sed without -i on spec" Bash command "sed -n '1,5p' $S"
no_nudge "Bash grep -i on spec" Bash command "grep -i todo $S"
no_nudge "Bash write elsewhere" Bash command "echo x > docs/notes/x.md"
no_nudge "Bash redirect to a .md.backup beside the spec" Bash command "printf x > $S.backup"
# Accepted false positives: telling these apart needs a shell parser. A spare
# nudge costs one reminder the writer ignores, since the review runs at handoff.
yes_nudge "Bash sed -i on another file then cat spec (accepted false positive)" Bash command "sed -i '' 's/a/b/' docs/notes/x.md && cat $S"
yes_nudge "Bash redirect inside a string literal (accepted false positive)" Bash command "echo \"literal > $S\""
raw_silent "malformed JSON" 'not json'
raw_silent "empty stdin" ''
raw_silent "payload without tool_input" '{"tool_name":"Write"}'
raw_silent "payload with a null command" '{"tool_name":"Bash","tool_input":{"command":null}}'
check_eq "nudge hook: no stderr noise across all calls" "$(wc -c < "$tmp/hk.err" | tr -d ' ')" "0"
```

- [ ] **Step 3: Run the tests and watch them fail**

Run from `~/.dotfiles`. Run the suite directly so its exit status survives; the grep is only a second look at the failures:

```
./test/render.sh > "$TMPDIR/render.out" 2>&1; echo "exit $?"; grep -E '^FAIL|check\(s\) failed|all checks passed' "$TMPDIR/render.out"
```

Expected: `FAIL claude settings(personal): hook, settings.json and statusline.sh under .claude`, `FAIL nudge hook: not executable`, `FAIL nudge hook: syntax`, every `yes_nudge` case failing with `no output`, and a non-zero failed count. The `no_nudge` cases pass trivially.

- [ ] **Step 4: Write the hook script**

Create `private_dot_claude/hooks/executable_spec-review-nudge.sh`:

```bash
#!/bin/bash
# PostToolUse hook. When a Write, Edit, or Bash call writes a superpowers spec
# or plan (docs/superpowers/specs/*.md or docs/superpowers/plans/*.md), remind
# the writer to run the cross-model-review skill before handing the document to
# George. Anything else, including malformed input, exits 0 with no output so a
# hook problem can never block a tool call.
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
# The .md must end the token, so x.md.backup does not count; the Write/Edit
# branch appends a space to the path so the same pattern applies.
RE_PATH="[^[:space:]\"']*docs/superpowers/(specs|plans)/[^[:space:]\"']+[.]md([[:space:]\"']|$)"
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

read -r -d '' NUDGE <<'EOF'
This file is a superpowers spec or plan. Before you hand it to George for review, run the `cross-model-review` skill on it. Sequence: finish the superpowers self-review and every fix that comes out of it first, then run the cross-model review on the final draft, immediately before the user review gate. A review counts only if the document has not changed since it ran. The one exception is edits that come out of George's triage of the findings; those are his decisions and do not need a second review.
EOF

jq -n -c --arg ctx "$NUDGE" \
  '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0
```

Note on `read -r -d ''`: it returns non-zero at end of input, which is expected; the script does not use `set -e`, so that is fine. The heredoc keeps the nudge text in one place with no escaping.

- [ ] **Step 5: Run the tests and watch them pass**

```
./test/render.sh > "$TMPDIR/render.out" 2>&1; echo "exit $?"; grep -E '^FAIL|check\(s\) failed|all checks passed' "$TMPDIR/render.out"
```

Expected: `all checks passed`, and the suite's own exit status is 0. If a `yes_nudge` Bash case fails, print the regex the case needs and test it in isolation:

```
cmd="echo x | tee -a docs/superpowers/specs/a.md"; RE_PATH="[^[:space:]\"']*docs/superpowers/(specs|plans)/[^[:space:]\"']+[.]md([[:space:]\"']|$)"; Q="[\"']?"; RE_TEE="(^|[[:space:]|;&])tee([[:space:]]+-[a-zA-Z]+)*[[:space:]]+${Q}${RE_PATH}"; [[ $cmd =~ $RE_TEE ]] && echo match || echo nomatch
```

- [ ] **Step 6: Commit**

```bash
cd ~/.dotfiles
git add private_dot_claude/hooks/executable_spec-review-nudge.sh test/render.sh
git commit -m "Add the spec review nudge hook

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: Register the hook and document it

**Files:**
- Modify: `.shared/claude-settings.json`
- Modify: `README.md` (last paragraph of the section `## Claude Code and Zed settings`)
- Modify: `test/render.sh` (append)

**Interfaces:**
- Consumes: `~/.claude/hooks/spec-review-nudge.sh` from Task 1.
- Produces: `hooks.PostToolUse[0]` in the rendered `~/.claude/settings.json`, which Task 3's doctor check reads.

- [ ] **Step 1: Append the settings assertions to `test/render.sh`**

```sh
# Task 2 (2026-10-11): nudge hook registered in shared Claude settings
for t in personal work; do
  c="$tmp/$t/.claude/settings.json"
  check_eq "claude settings($t): one PostToolUse hook group" "$(jq -r '.hooks.PostToolUse | length' "$c")" "1"
  check_eq "claude settings($t): hook matcher" "$(jq -r '.hooks.PostToolUse[0].matcher' "$c")" "Write|Edit|Bash"
  check_eq "claude settings($t): hook type" "$(jq -r '.hooks.PostToolUse[0].hooks[0].type' "$c")" "command"
  check_eq "claude settings($t): hook command" "$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$c")" "~/.claude/hooks/spec-review-nudge.sh"
  check_eq "claude settings($t): no other hook events" "$(jq -c '.hooks | keys' "$c")" '["PostToolUse"]'
done
check_fgrep "README: nudge hook documented" "$SRC/README.md" 'hooks/spec-review-nudge.sh'
check_fgrep "README: skill is hand-managed" "$SRC/README.md" '~/.claude/skills/cross-model-review/SKILL.md'
check_fgrep "README: agent is hand-managed" "$SRC/README.md" '~/.claude/agents/cross-model-reviewer.md'
```

- [ ] **Step 2: Run the tests and watch the new ones fail**

```
./test/render.sh > "$TMPDIR/render.out" 2>&1; echo "exit $?"; grep -E '^FAIL|check\(s\) failed|all checks passed' "$TMPDIR/render.out"
```

Expected: the five `claude settings(...)` hook checks fail for both machine kinds (`got 'null'` or `got ''`), the three README checks fail, nothing else.

- [ ] **Step 3: Add the hook entry to `.shared/claude-settings.json`**

Add a `hooks` key. Keys in this file are alphabetical; `hooks` goes after `extraKnownMarketplaces` and before `model`:

```json
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/spec-review-nudge.sh"
          }
        ]
      }
    ]
  },
```

Check the file still parses:

```
jq . .shared/claude-settings.json > /dev/null && echo ok
```

- [ ] **Step 4: Update the README**

In `README.md`, under `## Claude Code and Zed settings`, replace the last paragraph's final sentence:

```
Nothing else under `~/.claude` is managed; skills are an open question, recorded under Future work in `docs/superpowers/specs/2026-10-04-modern-cli-tools-design.md`.
```

with:

```
`~/.claude/hooks/spec-review-nudge.sh` is a PostToolUse hook, registered in the shared settings, that fires when a tool call writes a superpowers spec or plan and reminds Claude to run the `cross-model-review` skill before handing the document over. That skill, at `~/.claude/skills/cross-model-review/SKILL.md`, and the read-only agent it dispatches, at `~/.claude/agents/cross-model-reviewer.md`, are hand-managed and not in this repo; `dotfiles-doctor` fails when either is missing. The design is in `docs/superpowers/specs/2026-10-11-cross-model-spec-review-design.md`. Nothing else under `~/.claude` is managed; skills in general are an open question, recorded under Future work in `docs/superpowers/specs/2026-10-04-modern-cli-tools-design.md`.
```

- [ ] **Step 5: Run the tests and watch them pass**

```
./test/render.sh > "$TMPDIR/render.out" 2>&1; echo "exit $?"; grep -E '^FAIL|check\(s\) failed|all checks passed' "$TMPDIR/render.out"
```

Expected: `exit 0` and `all checks passed`. The existing `claude settings($t): the shared file when there is no local file` check compares the whole rendered file against the shared file, so it passes automatically with the new key.

- [ ] **Step 6: Commit**

```bash
cd ~/.dotfiles
git add .shared/claude-settings.json README.md test/render.sh
git commit -m "Register the spec review nudge hook

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Doctor checks for the hand-managed files

**Files:**
- Modify: `dot_local/bin/executable_dotfiles-doctor.tmpl` (the header comment on line 3, and a new section after the `echo "claude status line"` block)
- Modify: `test/render.sh` (append)

**Interfaces:**
- Consumes: the paths `~/.claude/skills/cross-model-review/SKILL.md` and `~/.claude/agents/cross-model-reviewer.md` (Tasks 5 and 4), and `hooks.PostToolUse` in settings (Task 2).
- Produces: `dotfiles-doctor` fails with a pointer to the spec when either file is missing.

- [ ] **Step 1: Append the doctor-source assertions to `test/render.sh`**

The existing doctor tests assert on the rendered doctor source with `check_grep`. Find the variable they use (`d=` near the line reading `check_grep "doctor: statusLine wired"`) and reuse it:

```sh
# Task 3 (2026-10-11): doctor checks the cross-model review files
check_grep "doctor: section for cross-model review" "$d" '^echo "claude cross-model review"'
check_fgrep "doctor: skill file checked" "$d" '$HOME/.claude/skills/cross-model-review/SKILL.md'
check_fgrep "doctor: agent file checked" "$d" '$HOME/.claude/agents/cross-model-reviewer.md'
check_fgrep "doctor: missing file names the spec" "$d" 'docs/superpowers/specs/2026-10-11-cross-model-spec-review-design.md'
check_fgrep "doctor: hook wired in settings" "$d" 'spec-review-nudge.sh'
check_grep "doctor: header mentions the review files" "$d" 'cross-model review'
```

- [ ] **Step 2: Run the tests and watch the new ones fail**

```
./test/render.sh > "$TMPDIR/render.out" 2>&1; echo "exit $?"; grep -E '^FAIL|check\(s\) failed|all checks passed' "$TMPDIR/render.out"
```

Expected: the six `doctor:` checks above fail, nothing else.

- [ ] **Step 3: Add the doctor section**

In `dot_local/bin/executable_dotfiles-doctor.tmpl`, change the header comment line

```
# signing, PATH, the Brewfile, config drift, the Claude Code status line,
```

to

```
# signing, PATH, the Brewfile, config drift, the Claude Code status line and
# cross-model review files,
```

Then insert this block after the `claude status line` block (after the line beginning `case "$sl_out" in`) and before `echo "startup"`:

```sh
echo "claude cross-model review"
spec_doc="docs/superpowers/specs/2026-10-11-cross-model-spec-review-design.md"
for f in "$HOME/.claude/skills/cross-model-review/SKILL.md" "$HOME/.claude/agents/cross-model-reviewer.md"; do
  if [ -f "$f" ]; then pass "${f#"$HOME"/} present"; else fail "${f#"$HOME"/} missing: hand-managed, see $spec_doc in ~/.dotfiles"; fi
done
if [ -x "$HOME/.claude/hooks/spec-review-nudge.sh" ]; then pass "spec-review-nudge.sh executable"; else fail "spec-review-nudge.sh missing or not executable"; fi
check "settings.json PostToolUse nudge hook" "$(jq -r '[.hooks.PostToolUse[]?.hooks[]?.command] | index("~/.claude/hooks/spec-review-nudge.sh") != null' "$HOME/.claude/settings.json" 2>/dev/null)" "true"
```

- [ ] **Step 4: Run the tests and watch them pass**

```
./test/render.sh > "$TMPDIR/render.out" 2>&1; echo "exit $?"; grep -E '^FAIL|check\(s\) failed|all checks passed' "$TMPDIR/render.out"
```

Expected: `exit 0` and `all checks passed`. Also confirm the template still renders and is valid sh:

```
chezmoi execute-template < dot_local/bin/executable_dotfiles-doctor.tmpl | sh -n && echo "doctor: sh -n ok"
```

- [ ] **Step 5: Commit**

```bash
cd ~/.dotfiles
git add dot_local/bin/executable_dotfiles-doctor.tmpl test/render.sh
git commit -m "Make the doctor check the cross-model review files

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: The read-only reviewer agent

**Files:**
- Create: `~/.claude/agents/cross-model-reviewer.md` (hand-managed, not in any repo)

**Interfaces:**
- Consumes: nothing.
- Produces: an agent named `cross-model-reviewer` that Task 5 dispatches with `subagent_type: "cross-model-reviewer"` and a `model` override. Its report starts with `Reviewer model: <id>` and lists at most ten numbered findings with severity `blocking`, `should-fix`, or `minor`.

- [ ] **Step 1: Create the agent file**

```
mkdir -p ~/.claude/agents
```

Write `~/.claude/agents/cross-model-reviewer.md`:

```markdown
---
name: cross-model-reviewer
description: Read-only reviewer for superpowers specs and plans. Dispatched by the cross-model-review skill with an explicit model override so that it runs on a different model from the writer. Not for direct use.
tools: Read, Grep, Glob
---

You review a design spec or an implementation plan that another agent wrote. You run on a different model from that agent, and you start with no knowledge of the conversation that produced the document. Your job is to find what is wrong with it. You cannot edit, create, or delete files; you have only Read, Grep, and Glob. Use them freely to read the document, the spec it implements, and anything in the repository you need to judge feasibility.

## Report format

The first line of your report must be exactly:

Reviewer model: <the model named in your system prompt>

If nothing in your system prompt or environment names the model you are running as, write exactly `Reviewer model: unknown`. Do not guess.

Then either the single line `No findings.` or a numbered list of at most ten findings, most severe first. Each finding has, on its own lines:

- **Severity:** `blocking`, `should-fix`, or `minor`.
- **Location:** the section heading or task number it points at.
- **Problem:** one to three sentences.
- **Suggested fix:** one to three sentences.

No praise. No summary of what the document does well. No preamble before the model line and no closing remarks after the last finding.

## What to look for in a spec

- Ambiguity: a requirement that could be read two ways.
- Internal contradictions between sections.
- Missing requirements and unhandled edge cases.
- Success criteria that cannot be verified.
- Scope creep: features that do not serve the stated problem.
- Infeasibility against the actual codebase. Read the code to check.

## What to look for in a plan

Read the spec the plan implements first; the dispatch names it.

- Spec requirements with no task that implements them.
- Task ordering or dependency errors.
- Tasks that do not include a test.
- Steps that would not work as written: wrong paths, wrong APIs, commands that do not exist. Check paths against the repository.
- Steps too vague to execute without guessing.

## Rules

- Report only problems. A finding must point at something that would go wrong, not a stylistic preference.
- Do not rewrite the document or propose a new design. Suggest the smallest fix for each finding.
- If the document or its spec is missing or unreadable, say so as a single `blocking` finding and stop.
```

- [ ] **Step 2: Confirm Claude Code sees the agent**

Start a new Claude Code session in any directory and run `/agents`. Expected: `cross-model-reviewer` is listed under user agents with tools Read, Grep, Glob. If it is not listed, check the frontmatter: `name`, `description`, and `tools` must be the only keys, and the file must start with `---` on line 1.

- [ ] **Step 3: Smoke-test the dispatch**

In that session, ask Claude: "Dispatch the cross-model-reviewer agent with model opus on `~/.dotfiles/docs/superpowers/specs/2026-10-11-cross-model-spec-review-design.md` and show me its first line." Expected: the first line is `Reviewer model:` followed by an opus identifier, and the agent did not attempt a Write or Edit. If the agent tried to edit, the `tools` line is wrong. If the line says `unknown`, the subagent's prompt does not carry its model; record that in the spec under a `## Known deviations` heading, because the skill's family check will then always ask George.

Then open `/tasks` in that session and find the dispatched agent. Expected: it shows the model that actually ran, and that model is opus. This is the runtime truth the self-report is checked against. Also note whether the Agent tool's own result text reported which model ran, independent of the agent's report. If it did, that is the authoritative source the skill's Step 5 prefers; record the field name in the skill.

No commit: this file is hand-managed.

---

### Task 5: The `cross-model-review` skill

**Files:**
- Create: `~/.claude/skills/cross-model-review/SKILL.md` (hand-managed, not in any repo)

**Interfaces:**
- Consumes: the `cross-model-reviewer` agent from Task 4; the nudge text from Task 1 names this skill.
- Produces: the procedure the writer follows from the nudge to the resumed superpowers flow.

- [ ] **Step 1: Create the skill file**

```
mkdir -p ~/.claude/skills/cross-model-review
```

Write `~/.claude/skills/cross-model-review/SKILL.md`:

```markdown
---
name: cross-model-review
description: Dispatch a clean-context reviewer on a different model to critique a spec or plan, then triage its findings with George one at a time. Use after the superpowers self-review of a spec or plan, immediately before handing it to George, or whenever George asks for a second-model review of a document.
---

# Cross-model review

A fresh agent on a different model reviews a superpowers spec or plan. You then walk George through its findings one at a time. George decides every change. You never apply a finding on your own, and you never revise the document because of the review without his choice.

## When to run it

- After the superpowers self-review and every fix that came out of it, on the final draft, immediately before the user review gate in brainstorming or the execution-method choice in writing-plans.
- Whenever George asks for a second-model review of a document.
- Not after edits that came out of George's triage. Those are his decisions.

Run it once per handoff. If the document changes after the review for any reason other than triage, the review is stale; see step 5.

## Step 1: Choose the reviewer model

Your system prompt names the model you are running as.

| You are | Reviewer `model` |
|---------|------------------|
| Fable   | `opus`           |
| Opus    | `fable`          |
| Anything else | `fable`    |

## Step 2: For a plan, find its spec

Read the plan's `**Spec:**` header line. Resolve the path relative to the repository root and confirm the file exists. If the header is missing, or the path does not resolve, ask George which spec the plan implements. One question. Never guess from filenames.

A spec needs nothing here.

## Step 3: Record what the reviewer will see

Hash the document, and for a plan also its spec:

```
shasum -a 256 <absolute path to document> [<absolute path to spec>]
```

Announce the dispatch in one message that contains the reviewer model and the complete 64-character hashes. Never abbreviate them; the later comparisons are made against this message. For example:

> Dispatching the cross-model review. Reviewer: opus.
> sha256 plan `3f2a9c1d7e8b4a6f0c2d5e9b1a7f3c8e6d4b2a0f9e8c7d6b5a4f3e2d1c0b9a8f`
> sha256 spec `9c1d3f2a8e7b6a5f4c3d2e1b0a9f8e7d6c5b4a3f2e1d0c9b8a7f6e5d4c3b2a1f`

Those hashes stay in the transcript so they survive compaction.

## Step 4: Dispatch

Use the Agent tool with:

- `subagent_type`: `cross-model-reviewer`
- `model`: the value from Step 1
- `prompt`, for a spec:

  > Review this spec: `<absolute path>`.

  for a plan:

  > Review this plan: `<absolute path>`. It implements the spec at `<absolute path>`.

Pass nothing else. No summary of the conversation, no hints about what you are worried about. The reviewer inherits the project's CLAUDE.md on purpose; it inherits none of this conversation.

## Step 5: Validate the return

Check all of these before presenting anything:

1. **Complete.** The Agent call returned a report, not an error, a timeout, or text that stops mid-finding.
2. **Model line.** The first line is `Reviewer model: <something>`.
3. **Different family.** The reported model's family differs from yours: fable versus opus. Compare families, not strings; the reviewer may name itself with an alias or a full model ID. `Reviewer model: unknown` fails this check. If the Agent result itself carries runtime model metadata, that is authoritative and the self-reported line is a fallback. George can confirm the real model in the `/tasks` view.
4. **Still fresh.** Re-run the `shasum` from Step 3. Every hash matches.

If any check fails, tell George in one line that the cross-model review did not complete and which check failed, then ask whether to retry or proceed without it. Never substitute your own model. Never present a same-model or stale review as a cross-model review.

**Zero findings.** If the report has the model line and then `No findings.`, say so in one line, naming the reviewer model, and resume the superpowers flow where you left off. Ask nothing. Edit nothing.

## Step 6: Triage, one finding at a time

Present findings in the reviewer's order. One finding per message. For each:

1. The reviewer's finding as returned: number, severity, location, problem, suggested fix. Do not rewrite it.
2. Your own assessment in one or two sentences: agree or disagree, and why. George wants both models' opinions.
3. The question: **apply**, **skip**, or **discuss**?

`discuss` opens a conversation about that finding. It ends when George says apply or skip.

**Running tally.** Every message after George's first decision opens with one line recording every decision so far, for example:

> Applied so far: 1, 2, 3, 5. Skipped: 4.

**Recovery.** If you cannot reconstruct George's decisions with certainty, after a compaction or an interrupted session, show him the tally you have and ask him to confirm or restart. Do not guess.

## Step 7: Apply and resume

After the last decision:

1. Re-run the `shasum` from Step 3 and compare against the recorded hashes. If anything changed, say so and ask how to proceed.
2. Apply every accepted finding in a single editing pass, exactly as decided. Nothing from a skipped finding.
3. Do not write a review log into the document.
4. Resume the superpowers flow where you left off: the spec review gate in brainstorming, or the execution-method choice in writing-plans. The edits from this pass do not need another review.
```

- [ ] **Step 2: Confirm Claude Code sees the skill**

In a new Claude Code session, type `/cross-model-review` and press Tab or Enter. Expected: the skill is recognised and its instructions load. If not, check that the directory name matches the `name` field and that the frontmatter has only `name` and `description`.

- [ ] **Step 3: Run the doctor**

```
dotfiles-doctor 2>&1 | sed -n '/claude cross-model review/,/^startup/p'
```

Expected, after Task 3 is applied (Task 6 Step 1) and Task 4's file exists:

```
claude cross-model review
  [ OK ] .claude/skills/cross-model-review/SKILL.md present
  [ OK ] .claude/agents/cross-model-reviewer.md present
  [ OK ] spec-review-nudge.sh executable
  [ OK ] settings.json PostToolUse nudge hook
```

If Task 6 Step 1 has not run yet, the last two lines fail; that is expected until `chezmoi apply`.

No commit: this file is hand-managed.

---

### Task 6: Apply and verify end to end

**Files:**
- None created. Uses a throwaway spec at `~/src/personal-site/docs/superpowers/specs/2026-10-11-throwaway-design.md`, deleted at the end.

**Interfaces:**
- Consumes: everything from Tasks 1 to 5.
- Produces: confidence that the whole chain works on the live machine, and a note of anything that did not.

- [ ] **Step 1: Apply the dotfiles and run the doctor**

```
chezmoi apply
ls -l ~/.claude/hooks/spec-review-nudge.sh
jq '.hooks' ~/.claude/settings.json
dotfiles-doctor; echo "exit $?"
```

Expected: the hook file is executable, `jq` prints the PostToolUse entry, and the doctor exits 0 with the four `claude cross-model review` lines all `[ OK ]`.

- [ ] **Step 2: Confirm the hook fires in a live session on Write and on Bash**

Start a new Claude Code session in `~/src/personal-site`. Ask:

> Write a two-paragraph throwaway spec to `docs/superpowers/specs/2026-10-11-throwaway-design.md` using the Write tool. It should describe adding a `/healthz` route that returns the git commit hash. Then tell me verbatim whether any hook text appeared after the write.

Expected: Claude reports seeing text beginning "This file is a superpowers spec or plan." Then ask:

> Now append one sentence to that file with a bash heredoc or redirect, and tell me again whether hook text appeared.

Expected: it appeared again.

- [ ] **Step 3: Happy path, including one review for several edits**

In the same session, ask Claude to treat the throwaway file as a real spec: "Run the superpowers self-review on it, fix whatever you find, then do what the hook text says." Watch for, in order:

1. The self-review edits happen first, each with a nudge, and no dispatch yet.
2. One dispatch message naming the reviewer model (`opus`, since this machine's default is Fable) and the sha256.
3. A return whose first line names an opus model.
4. Findings presented one at a time with apply/skip/discuss.

Decide a mix: apply at least one, skip at least one. Expected: the tally line appears from the second finding onward; the editing pass changes only the applied ones; the edits produce nudges but no second dispatch; the flow then resumes with the spec review gate question.

- [ ] **Step 4: Stale document**

Ask Claude to dispatch the review again. While the reviewer is running, edit the throwaway file by hand in another terminal:

```
echo "Edited during review." >> ~/src/personal-site/docs/superpowers/specs/2026-10-11-throwaway-design.md
```

Expected: when the reviewer returns, Claude reports a hash mismatch and asks whether to re-run or proceed, without presenting findings.

- [ ] **Step 5: Forced model override**

First confirm the environment variable names in the installed Claude Code:

```
grep -rho 'CLAUDE_CODE_SUBAGENT_MODEL[A-Z_]*' "$(dirname "$(readlink -f "$(command -v claude)")")" 2>/dev/null | sort -u
```

Expected: both `CLAUDE_CODE_SUBAGENT_MODEL` and `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`. The first names the model, the second is an on/off flag that makes it override per-dispatch model choices. Start a new session with the model set to the writer's own family and the flag on:

```
CLAUDE_CODE_SUBAGENT_MODEL=fable CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 claude
```

Ask for the review of the throwaway spec. Expected: Claude reports that the cross-model review did not complete because the reviewer reported the same model family, and asks whether to retry or proceed. Confirm in `/tasks` that the subagent did run on fable. If the grep shows only one of the two variables, or neither, record in the spec's `## Known deviations` that the case could not be exercised on this version and move on.

- [ ] **Step 6: The doctor fails when a hand-managed file is missing**

```
mv ~/.claude/skills/cross-model-review/SKILL.md ~/.claude/skills/cross-model-review/SKILL.md.aside
dotfiles-doctor > "$TMPDIR/doctor.out" 2>&1; echo "exit $?"
grep -F 'cross-model-review/SKILL.md' "$TMPDIR/doctor.out"
mv ~/.claude/skills/cross-model-review/SKILL.md.aside ~/.claude/skills/cross-model-review/SKILL.md
dotfiles-doctor > /dev/null 2>&1; echo "exit $?"
```

Expected: the first run prints `exit 1` and a `[FAIL] .claude/skills/cross-model-review/SKILL.md missing: hand-managed, see docs/superpowers/specs/2026-10-11-cross-model-spec-review-design.md in ~/.dotfiles` line. The second run prints `exit 0`.

- [ ] **Step 7: Clean up and record**

```
rm ~/src/personal-site/docs/superpowers/specs/2026-10-11-throwaway-design.md
cd ~/src/personal-site && git status --short docs/superpowers
```

Expected: nothing left behind. If any step above did not behave as expected, or a step above asked for one, write the deviation into the spec under a `## Known deviations` heading in `~/.dotfiles/docs/superpowers/specs/2026-10-11-cross-model-spec-review-design.md` and commit it:

```bash
cd ~/.dotfiles
git add docs/superpowers/specs/2026-10-11-cross-model-spec-review-design.md
git commit -m "Record what the end-to-end check found

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
