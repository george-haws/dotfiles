# Cross-model review of specs and plans

**Date:** 2026-10-11
**Status:** Implemented 2026-10-11 on the cross-model-review branch and applied to George's machine; see Known deviations.

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
   - For `Bash`, `tool_input.command`, but only the parts of it that write.
     A path counts when it follows a redirect (`>` or `>>`), is an argument
     to `tee`, or appears in an in-place edit (`sed -i` or `perl -i`). A path
     that only appears as a read, such as `cat`, `grep`, `git diff`, or
     `shasum`, does not count.
3. If a counted path matches `docs/superpowers/specs/*.md` or
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
takes the path from a variable or a Python heredoc that opens the file, is
not detected. This is acceptable: the superpowers skills write specs and
plans with Write, and auto mode's preference for Bash produces heredocs,
redirects, and in-place `sed` edits, which the string match does catch.

**Nudge text:**

> This file is a superpowers spec or plan. Before you hand it to George for
> review, run the `cross-model-review` skill on it. Sequence: finish the
> superpowers self-review and every fix that comes out of it first, then run
> the cross-model review on the final draft, immediately before the user
> review gate. A review counts only if the document has not changed since it
> ran. The one exception is edits that come out of George's triage of the
> findings; those are his decisions and do not need a second review.

**Subagent variant.** When the hook input carries a non-empty `agent_id`, the
write came from inside a subagent, which cannot triage findings with George.
The hook then emits the same JSON structure with this text instead:

> This file is a superpowers spec or plan, and you are running as a subagent.
> Do not run the cross-model review yourself. When you report back, tell your
> caller that you changed this spec or plan so it can run the
> `cross-model-review` skill before the document goes to George.

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

Nothing from the parent conversation is passed. Isolation here means no
inherited conversation history. The reviewer does inherit the applicable
CLAUDE.md and project instructions, on purpose: they carry repository
conventions and warnings, such as a framework version that differs from
training data, that a feasibility check needs.

**Recording what the reviewer sees.** Immediately before dispatch, the writer
computes a SHA-256 of the document, and for a plan also of its spec, and
states the hashes in the message that announces the dispatch. Hashing is a
read, so it does not trigger the nudge. The hashes are compared twice: when
the reviewer returns, and again before the editing pass. A mismatch means the
reviewed version is stale. The writer says so and asks George whether to
re-run the review or proceed on the stale findings. It does not proceed on
its own.

**Verifying independence.** When the agent returns, the writer reads the
`Reviewer model:` line and compares model families with its own, fable
against opus, not strings against strings, since the reviewer may name itself
with an alias or a full model ID. The review counts only if:

- The agent returned a complete report with that line present.
- The reported family differs from the writer's family.
- The document hashes still match.

This check is a self-report by the reviewer, not a runtime attestation. It
catches the obvious failure, a forced-model environment override, and a
truncated return. It cannot catch a model that misreports itself. If the
Agent tool result turns out to carry model metadata, that becomes the
authoritative source and the self-report is a fallback; implementation
checks this.

If any check fails, including an Agent call that errors, times out, or
returns truncated output, the writer tells George in one line that the
cross-model review did not complete and why, and asks whether to retry or
proceed without it. The writer never substitutes its own model and never
presents a same-model review as cross-model.

**Zero findings.** If the report has the model line and then says there is
nothing to report, the writer relays that in one line, naming the reviewer
model, and resumes the superpowers flow directly. No decisions are requested
and no files are touched.

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
writer re-hashes the document and compares against the hash recorded at
dispatch. If it has changed, the writer says so and asks how to proceed.

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
   - `Bash` with `tee` or `sed -i` on a spec path: nudge JSON.
   - An absolute path outside the current repository that still matches the
     directory pattern: nudge JSON.
   - A markdown file elsewhere, a non-markdown file inside the spec
     directory, and malformed JSON: no output, exit 0.
   - `Bash` commands that only read a spec: `cat`, `grep`, `git diff`, and
     `shasum` on a spec path: no output, exit 0.
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
   - A reviewer that returns zero findings ends with the one-line report,
     no triage, and the superpowers flow resumes.
   - Editing the spec while the reviewer is running produces a hash mismatch
     and a stale-review question instead of triage.
   - With the subagent model force environment variable set to the writer's
     own model, the writer reports the review as not completed instead of
     presenting findings.
   Delete the throwaway spec afterward.

Reviewer launch failures and truncated output are not in the test plan
because there is no reliable way to provoke them. Component 3 defines the
behavior.

## Known deviations

1. The Agent tool result carries no model field (only agent id, token count,
   tool uses, and duration), so the reviewer's self-reported `Reviewer model:`
   line is the only automatic independence check; the `/tasks` view is the
   manual confirmation. The smoke test from a fable parent returned
   `Reviewer model: claude-opus-5-5`.
2. The hook test `is_nudge` asserts the JSON structure, exit status, the
   opening sentence, and five key phrases rather than the exact full JSON the
   Testing section asks for.
3. `RE_PATH` also matches nested paths such as
   `docs/superpowers/specs/sub/x.md`; the spec's `specs/*.md` is read as "any
   markdown under that directory".
4. The hook's Bash matching does not detect writes into a spec path by `cp`,
   `mv`, `git checkout --`, `git restore`, or `git mv`, nor `sed --in-place`;
   and `perl -M...` can false-positive as an in-place edit. These join the
   accepted limitations.
5. `dotfiles-doctor` exits 1 on George's machine because of 14 failures
   unrelated to this work (the Oct 4 Brewfile and CLI tools were never
   applied; `dotfiles-capture` is not installed). The cross-model section
   itself is all OK.
6. The doctor's failure message points at this spec, but the verbatim bodies
   of the two hand-managed files live in the plan
   (`docs/superpowers/plans/2026-10-11-cross-model-spec-review.md`, Tasks 4
   and 5); a fresh machine rebuilds them from there.
7. The skill's stale-review wording offers "retry or proceed without it" where
   this spec says "re-run the review or proceed on the stale findings"; the
   skill is the stricter of the two and stands.
8. End-to-end Steps 3, 4, and 5 of the plan's Task 6 (live triage with mixed
   decisions, hash mismatch during review, forced-model environment variable)
   need multi-turn sessions with George and have not been run; Steps 1, 2, 6,
   and 7 passed on 2026-10-11.
9. Subagent handling (the `agent_id` variant in Component 1) was added after
   the final review found the hook firing inside subagents; it was not in the
   original design.

## Out of scope

- Reviewing documents other than superpowers specs and plans.
- Automatic re-review after triage edits.
- A Stop hook gate. See "Best-effort, not a hard gate" above.
- Changing the superpowers plugin itself or upstreaming this behavior.
- Any model other than fable and opus as the reviewer.
