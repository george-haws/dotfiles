# Cross-model review of specs and plans

**Date:** 2026-10-11
**Status:** Approved design, revised after cross-model review, not yet implemented

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
- **Best-effort, not a hard gate.** The hook reminds; it cannot force the
  dispatch. A writer can read the reminder and still hand off without a review.
  George accepts this. If missed reviews turn out to happen in practice, the
  upgrade path is a Stop hook that greps the session transcript for an
  unreviewed spec write and blocks the turn. That gate is not built now because
  it would fire on every brainstorming iteration, not only at handoff, and a
  Stop hook has no soft mode.
- **Loose user config, not a plugin or fork.** The hook entry and script go in
  the chezmoi-managed dotfiles. The skill and the reviewer agent go in
  `~/.claude/skills/` and `~/.claude/agents/`, next to George's other custom
  skills, which chezmoi does not manage.

## Components

### 1. The nudge hook

**Location:** `~/.claude/hooks/spec-review-nudge.sh`, deployed by chezmoi from
`~/.dotfiles/private_dot_claude/hooks/executable_spec-review-nudge.sh`.

**Registration:** a `PostToolUse` entry in
`~/.dotfiles/.shared/claude-settings.json` with matcher `Write|Edit|Bash`.
The template `settings.json.tmpl` already merges this file, so no template
change is needed.

**Behavior:**

1. Read the hook payload JSON from stdin.
2. Determine the candidate text to match:
   - For `Write` and `Edit`, `tool_input.file_path`.
   - For `Bash`, `tool_input.command`. This catches heredocs and redirects
     that create or modify a spec or plan.
3. If the text contains a path matching `docs/superpowers/specs/*.md` or
   `docs/superpowers/plans/*.md`, print exactly this JSON and exit 0:

   ```json
   {
     "hookSpecificOutput": {
       "hookEventName": "PostToolUse",
       "additionalContext": "<nudge text>"
     }
   }
   ```

4. Otherwise exit 0 with no output.

The script depends only on `jq` and bash. It must never block or fail the
tool call: on any parse error it exits 0 silently.

**Known limitation.** The Bash case is a string match on the command text, not
a file event. A command that writes a spec indirectly, such as a script that
takes the path from a variable, is not detected. This is acceptable: the
superpowers skills write specs and plans with Write, and auto mode's
preference for Bash produces heredocs and redirects, which the string match
does catch.

**Nudge text:**

> This file is a superpowers spec or plan. Before you hand it to George for
> review, run the `cross-model-review` skill on it. Sequence: finish the
> superpowers self-review and every fix that comes out of it first, then run
> the cross-model review on the final draft, immediately before the user
> review gate. A review counts only if the document has not changed since it
> ran. The one exception is edits that come out of George's triage of the
> findings; those are his decisions and do not need a second review.

The hook fires on every matching Write, Edit, or Bash call, including the
writer's own self-review fixes and the edits that come out of triage. The
nudge is idempotent by instruction: one review per handoff, on the final
draft. George can ask for another review at any time by invoking the skill
directly.

### 2. The reviewer agent

**Location:** `~/.claude/agents/cross-model-reviewer.md`. Not managed by
chezmoi.

**Tools:** `Read`, `Grep`, `Glob` only. No `Write`, `Edit`, `Bash`, or
`Agent`. Read-only is a tool-level fact, not an instruction. The agent can
still read any path on disk, including files outside the repository, which it
needs for feasibility checks.

**Model:** not set in the agent file. The skill passes the model on each
dispatch, and the Agent tool's `model` override takes precedence over the
agent definition.

**System prompt** carries the review brief so the skill does not re-paste it:

The first line of the report must state the model the reviewer is running
as, taken from its own system prompt, in the form `Reviewer model: <id>`.

For a spec, look for:

- Ambiguity: requirements that could be read two ways.
- Internal contradictions between sections.
- Missing requirements and unhandled edge cases.
- Success criteria that cannot be verified.
- Scope creep: features that do not serve the stated problem.
- Infeasibility against the actual codebase.

For a plan, look for:

- Spec requirements with no task that implements them.
- Task ordering or dependency errors.
- Tasks that do not include a test.
- Steps that would not work as written: wrong paths, wrong APIs, commands
  that do not exist.
- Steps too vague to execute without guessing.

Return at most ten findings, most severe first. Each finding has:

- A number.
- A severity: `blocking`, `should-fix`, or `minor`.
- The section or task it points at.
- The problem, in one to three sentences.
- A suggested fix, in one to three sentences.

No praise. No summary of what the document does well. If there is nothing to
report, say so in one line after the model line.

### 3. The `cross-model-review` skill

**Location:** `~/.claude/skills/cross-model-review/SKILL.md`. Not managed by
chezmoi.

**Frontmatter description:** "Dispatch a clean-context reviewer on a different
model to critique a spec or plan, then triage its findings with George one at
a time. Use after the superpowers self-review of a spec or plan, immediately
before handing it to George, or whenever George asks for a second-model review
of a document."

**Model selection.** The writer reads its own model from its system prompt.

| Writer | Reviewer |
|--------|----------|
| Fable  | opus     |
| Opus   | fable    |
| Anything else | fable |

**Finding the spec for a plan.** Read the plan's `**Spec:**` header, which the
writing-plans template requires. Resolve the path relative to the repository
and verify the file exists. If the header is missing or the path does not
resolve, ask George which spec the plan implements. Never match on filenames.

**Dispatch.** One `cross-model-reviewer` agent via the Agent tool with the
`model` override from the table. The prompt contains only:

- Whether the document is a spec or a plan.
- The absolute path of the document under review.
- For a plan, the absolute path of its spec.

Nothing else from the conversation is passed. The reviewer starts clean.

**Verifying independence.** When the agent returns, the writer reads the
`Reviewer model:` line and compares it with its own model. The review counts
only if:

- The agent returned a complete report with that line present.
- The reported model differs from the writer's model.

If either check fails, including an Agent call that errors, times out, or
returns truncated output, the writer tells George in one line that the
cross-model review did not complete and why, and asks whether to retry or
proceed without it. The writer never substitutes its own model and never
presents a same-model review as cross-model.

### 4. Triage

After a valid review returns, the writer presents findings one at a time,
following George's standing one-question-at-a-time rule. Each presentation
shows:

1. The reviewer's finding as returned, including severity and location. The
   writer does not rewrite it.
2. The writer's own one-line assessment: agree or disagree, and why. This
   gives George both models' opinions on each point.
3. A choice: **apply**, **skip**, or **discuss**.

`discuss` opens a conversation about that finding; it ends when George picks
apply or skip.

**Running tally.** Each time George decides, the writer's next message opens
with one line recording every decision so far, for example
`Applied so far: 1, 2, 3, 5. Skipped: 4.` This keeps the decisions in the
recent transcript so they survive context compaction.

**Recovery.** If the writer cannot reconstruct George's decisions with
certainty, after compaction or an interrupted session, it asks him to confirm
the tally or restart triage. It does not guess. Before the editing pass, the
writer re-reads the document and confirms it matches the version the reviewer
saw. If it has changed, the writer says so and asks how
to proceed.

**Editing pass.** After the last finding, the writer applies every accepted
finding in a single pass, preserving exactly the decisions made. It then
resumes the normal superpowers flow at the point where it left off: the spec
review gate in brainstorming, or the execution-method choice in writing-plans.

No review log is written into the document.

## Files touched

| File | Managed by | Change |
|------|-----------|--------|
| `~/.dotfiles/.shared/claude-settings.json` | chezmoi | Add `hooks.PostToolUse` entry |
| `~/.dotfiles/private_dot_claude/hooks/executable_spec-review-nudge.sh` | chezmoi | New hook script |
| `~/.dotfiles/dot_local/bin/executable_dotfiles-doctor.tmpl` | chezmoi | Check that the skill and agent files exist |
| `~/.claude/skills/cross-model-review/SKILL.md` | hand | New skill |
| `~/.claude/agents/cross-model-reviewer.md` | hand | New agent |

## Testing

1. **Hook unit test**, added to the dotfiles `test/` suite. Pipe hand-written
   payloads into the script and compare stdout against the exact expected
   JSON, not just non-empty output. Cases:
   - `Write` to a spec path and to a plan path: nudge JSON.
   - `Edit` to a spec path: nudge JSON.
   - `Bash` with a heredoc targeting a spec path: nudge JSON.
   - `Bash` with a redirect targeting a plan path: nudge JSON.
   - An absolute path outside the current repository that still matches the
     directory pattern: nudge JSON.
   - A markdown file elsewhere, a non-markdown file inside the spec
     directory, a Bash command that only reads a spec, and malformed JSON:
     no output, exit 0.
2. **Doctor check.** `dotfiles-doctor` fails if
   `~/.claude/skills/cross-model-review/SKILL.md` or
   `~/.claude/agents/cross-model-reviewer.md` is missing, since chezmoi
   deploys the hook but not those files.
3. **Render test.** Run `chezmoi apply` and confirm `~/.claude/settings.json`
   contains the PostToolUse entry and `~/.claude/hooks/spec-review-nudge.sh`
   is executable.
4. **End-to-end**, in a fresh Claude Code session with a throwaway spec under
   `docs/superpowers/specs/`:
   - Happy path: the nudge appears, the writer finishes its self-review before
     dispatching, the reviewer runs on the other model, and triage runs one
     finding at a time.
   - Several edits before self-review completes produce one review, on the
     final draft.
   - Mixed accept and skip decisions in one triage; the editing pass applies
     only the accepted ones.
   - Edits from triage do not trigger a second review.
   - A reviewer that returns zero findings ends with the one-line report and
     no triage.
   - With the subagent model force environment variable set to the writer's
     own model, the writer reports the review as not completed instead of
     presenting findings.
   Delete the throwaway spec afterward.

Reviewer launch failures and truncated output are not in the test plan
because there is no reliable way to provoke them. Component 3 defines the
behavior.

## Out of scope

- Reviewing documents other than superpowers specs and plans.
- Automatic re-review after triage edits.
- A Stop hook gate. See "Best-effort, not a hard gate" above.
- Changing the superpowers plugin itself or upstreaming this behavior.
- Any model other than fable and opus as the reviewer.
