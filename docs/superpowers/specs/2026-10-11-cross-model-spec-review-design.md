# Cross-model review of specs and plans

**Date:** 2026-10-11
**Status:** Approved design, not yet implemented

## Problem

The superpowers brainstorming and writing-plans skills end with a self-review
the writer runs on its own output. Both skills say explicitly that this is "a
checklist you run yourself, not a subagent dispatch." A model reviewing its own
spec shares its blind spots. George wants every spec and plan reviewed by a
fresh agent running a different model before he reads it, and he wants to
triage the findings himself rather than have the writer rewrite the document
on its own.

The superpowers plugin is a marketplace cache (version 6.3.0 at the time of
writing), so editing it in place is lost on the next update. The change has to
live in George's own config.

## Decisions already made

- **No automatic revision.** Findings are presented to George one at a time.
  He chooses an action per finding. The writer never applies a finding without
  that choice.
- **Hook-nudged, not hook-executed.** A hook makes the trigger deterministic,
  but the writer performs the dispatch through the Agent tool so the result
  arrives as a normal subagent return in the conversation. The hook does not
  run a headless `claude` process itself.
- **Loose user config, not a plugin or fork.** The hook entry goes in the
  chezmoi-managed shared settings. The skill goes in `~/.claude/skills/`, next
  to George's other custom skills.

## Components

### 1. The nudge hook

**Location:** `~/.claude/hooks/spec-review-nudge.sh`, deployed by chezmoi from
`~/.dotfiles/private_dot_claude/hooks/executable_spec-review-nudge.sh`.

**Registration:** a `PostToolUse` entry in
`~/.dotfiles/.shared/claude-settings.json` with matcher `Write|Edit`. The
template `settings.json.tmpl` already merges this file, so no template change
is needed.

**Behavior:**

1. Read the hook payload JSON from stdin.
2. Extract `tool_input.file_path`.
3. If the path matches `docs/superpowers/specs/*.md` or
   `docs/superpowers/plans/*.md`, print a JSON object whose
   `hookSpecificOutput.additionalContext` is the nudge text below and exit 0.
4. Otherwise exit 0 with no output.

The script depends only on `jq` and bash. It must never block or fail the
write: on any parse error it exits 0 silently.

**Nudge text:**

> This file is a superpowers spec or plan. Before handing it to George for
> review, invoke the `cross-model-review` skill on it, unless you have already
> run that review for this handoff. Edits made while triaging the reviewer's
> findings do not need a second review.

The hook fires on every Write or Edit to those paths, including the writer's
own self-review fixes and the edits that come out of triage. The nudge is
therefore idempotent by instruction: one review per handoff. George can ask
for another review at any time by invoking the skill directly.

### 2. The `cross-model-review` skill

**Location:** `~/.claude/skills/cross-model-review/SKILL.md`. Not managed by
chezmoi, consistent with the other custom skills in that directory.

**Frontmatter description:** "Dispatch a clean-context reviewer on a different
model to critique a spec or plan, then triage its findings with George one at
a time. Use after writing or revising a superpowers spec or plan, or whenever
George asks for a second-model review of a document."

**Model selection.** The writer reads its own model from its system prompt.

| Writer | Reviewer |
|--------|----------|
| Fable  | opus     |
| Opus   | fable    |
| Anything else | fable |

**Dispatch.** One `general-purpose` agent via the Agent tool with the `model`
override from the table. The prompt contains:

- The absolute path of the document under review.
- When the document is a plan, the absolute path of the spec it implements.
  The writer finds this from the plan's header or from the matching filename
  in `docs/superpowers/specs/`.
- The review brief below.

Nothing else from the conversation is passed. The reviewer starts clean.

**Review brief.** The reviewer is read-only. It must not edit, create, or
delete any file. It may read anything in the repository to check feasibility.

For a spec, it looks for:

- Ambiguity: requirements that could be read two ways.
- Internal contradictions between sections.
- Missing requirements and unhandled edge cases.
- Success criteria that cannot be verified.
- Scope creep: features that do not serve the stated problem.
- Infeasibility against the actual codebase.

For a plan, it looks for:

- Spec requirements with no task that implements them.
- Task ordering or dependency errors.
- Tasks that do not include a test.
- Steps that would not work as written: wrong paths, wrong APIs, commands that
  do not exist.
- Steps too vague to execute without guessing.

It returns at most ten findings, most severe first. Each finding has:

- A number.
- A severity: `blocking`, `should-fix`, or `minor`.
- The section or task it points at.
- The problem, in one to three sentences.
- A suggested fix, in one to three sentences.

No praise. No summary of what the document does well. If the reviewer finds
nothing, it says so in one line.

### 3. Triage

After the reviewer returns, the writer presents findings one at a time,
following George's standing one-question-at-a-time rule. Each presentation
shows:

1. The reviewer's finding as returned, including severity and location.
2. The writer's own one-line assessment: agree or disagree, and why. This
   gives George both models' opinions on each point.
3. A choice: **apply**, **skip**, or **discuss**.

`discuss` opens a conversation about that finding; it ends when George picks
apply or skip.

After the last finding, the writer applies every accepted finding in a single
editing pass. It then resumes the normal superpowers flow at the point where
it left off: the spec review gate in brainstorming, or the execution-method
choice in writing-plans.

No review log is written into the document.

## Files touched

| File | Change |
|------|--------|
| `~/.dotfiles/.shared/claude-settings.json` | Add `hooks.PostToolUse` entry |
| `~/.dotfiles/private_dot_claude/hooks/executable_spec-review-nudge.sh` | New hook script |
| `~/.claude/skills/cross-model-review/SKILL.md` | New skill |

## Testing

1. **Hook unit test.** Pipe hand-written payloads into the script. A spec path
   and a plan path each produce the nudge JSON. A path outside those
   directories, a non-markdown file in those directories, and malformed JSON
   each produce no output and exit 0.
2. **Render test.** Run `chezmoi apply` and confirm `~/.claude/settings.json`
   contains the PostToolUse entry and `~/.claude/hooks/spec-review-nudge.sh`
   is executable.
3. **End-to-end.** In a fresh Claude Code session, write a throwaway spec under
   `docs/superpowers/specs/`. Confirm the nudge appears, the writer dispatches
   an agent on the other model, and the triage runs one finding at a time.
   Delete the throwaway spec afterward.

## Out of scope

- Reviewing documents other than superpowers specs and plans.
- Automatic re-review after triage edits.
- Changing the superpowers plugin itself or upstreaming this behavior.
- Any model other than fable and opus as the reviewer.
