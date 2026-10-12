# Handoff: cross-model review follow-ups

**Date:** 2026-10-11
**Context:** The cross-model review of superpowers specs and plans is implemented, merged to `master`, and live on George's machine. Design: `docs/superpowers/specs/2026-10-11-cross-model-spec-review-design.md`. Plan: `docs/superpowers/plans/2026-10-11-cross-model-spec-review.md`. This document covers the two pieces of work left after the final review: a batch of small fixes, and a decision about whether the two hand-managed files should come under chezmoi.

Before either, run the live verification in the plan's Task 6, steps 3 to 5. It may change the priority of the items below.

## Part A: the follow-up fix batch

All of these came out of the task reviews and the final whole-branch review. None blocks use of the feature. They are grouped by file so one pass covers each file once. Line numbers are as of commit `2b02eb3`.

### A1. The plan carries a stale copy of the skill

- **Where:** `docs/superpowers/plans/2026-10-11-cross-model-spec-review.md:587`, inside the Task 5 verbatim `SKILL.md` block.
- **Problem:** The sentence "If the Agent result itself carries runtime model metadata, that is authoritative and the self-reported line is a fallback" was replaced in the live skill but not in the plan. The spec's Known deviation 6 tells a fresh machine to rebuild the skill from this block, so the stale wording would come back.
- **Fix:** Replace that sentence with the live skill's text from `~/.claude/skills/cross-model-review/SKILL.md:72`, and drop the trailing "George can confirm the real model in the `/tasks` view." sentence from both (see A2).

### A2. Skill wording

File: `~/.claude/skills/cross-model-review/SKILL.md` (hand-managed; also mirror each change into the plan's Task 5 block).

- **L72:** ends by saying the `/tasks` point twice. Delete the final sentence "George can confirm the real model in the `/tasks` view."
- **L72:** "fable versus opus" assumes the writer is one of those two. Reword to "differs from your own model's family".
- **L16:** "see step 5" covers only the check made when the reviewer returns. Point at both: "see Step 5 check 4 and Step 7.1".
- **L30:** "Resolve the path relative to the repository root" does not cover an absolute `**Spec:**` path or one relative to the plan file. Add: "Accept an absolute path as is; try plan-relative if repo-relative does not resolve."
- **L87:** `discuss` ends only in apply or skip. In practice George often wants a modified fix. Add a third outcome, "apply as amended", and carry the amendment into the editing pass. This is also a one-line change to the spec's Component 4.

### A3. Agent wording

File: `~/.claude/agents/cross-model-reviewer.md` (hand-managed; mirror into the plan's Task 4 block).

- **L13:** the template `Reviewer model: <the model named in your system prompt>` is not in backticks while L15's fallback is, and L13 names only "your system prompt" where L15 says "system prompt or environment". Make the two consistent.
- **L7:** "You run on a different model from that agent" is unverifiable by the reviewer and could discourage it from noticing a same-model run. Drop the sentence or soften to "You were dispatched to run on a different model".
- **L41:** "Tasks that do not include a test" flags plan tasks that legitimately have no test, such as hand-managed files. Add "unless the task is documentation or configuration with nothing to run".

### A4. Hook regex

File: `private_dot_claude/hooks/executable_spec-review-nudge.sh`. Tests in the Task 1 block of `test/render.sh`; add a case for each change.

- **L30, `RE_INPLACE`:** requires the first flag after `sed`/`perl` to contain `i`. Misses `sed -E -i`, `sed --in-place`, `perl -0pi`. False-positives on `perl -Mstrict`. Allow a run of flags before the `i` flag, accept `--in-place`, and exclude `-M` module flags.
- **L29, `RE_TEE`:** only single-dash flags. Accept `tee --append`.
- **L34-36, Write/Edit branch:** anchors `RE_PATH` with a no-whitespace prefix, so an absolute path containing a space is missed. Write and Edit hand over a literal path, so use a separate pattern for them, for example a `case` on `*docs/superpowers/specs/*.md|*docs/superpowers/plans/*.md`.
- **Known gaps to leave alone:** `cp`, `mv`, `git checkout --`, `git restore`, `git mv` into a spec path are not detected. The spec's Known deviation 4 accepts this. Do not build a shell parser.

### A5. Tests that check text rather than behavior

File: `test/render.sh`.

- **L686:** `check_grep ... 'cross-model review'` is satisfied by the doctor's section echo line, so it does not prove the header comment changed. Anchor on `'^# cross-model review files'`.
- **L685:** `check_fgrep ... 'spec-review-nudge.sh'` is satisfied by the executable check, so it does not prove the settings jq check exists. Grep for the literal `index("~/.claude/hooks/spec-review-nudge.sh")`.
- **L595, `is_nudge`:** asserts structure, exit status, the opening sentence and five phrases, not the exact full nudge text the spec's Testing 1 asks for. Add one `check_eq` of `additionalContext` against the full string, or accept the current form and leave Known deviation 2 as the record.

### A6. Doctor message

File: `dot_local/bin/executable_dotfiles-doctor.tmpl:106-108`.

- The failure message points at the spec, but the spec does not contain the files' bodies. Point at the plan instead, or at both: "see the plan's Tasks 4 and 5 for the file bodies". If Part B puts the files under chezmoi, this check and its message go away entirely.

### Suggested order

A1 and A2 together (one editing pass over the skill and its plan mirror), then A3, then A4 with its tests, then A5, then A6 unless Part B makes it moot. Run `./test/render.sh` directly and read its exit status after each repo change. Re-apply the hook with `chezmoi apply ~/.claude/hooks/spec-review-nudge.sh` after A4; the skill and agent files take effect in the next Claude Code process.

## Part B: should the skill and agent come under chezmoi?

### The decision as made

The spec chose "loose user config": the hook and settings under chezmoi, the skill and agent hand-managed in `~/.claude/skills/` and `~/.claude/agents/`, matching George's other custom skills. The doctor fails when either file is missing, and the spec's Known deviation 6 points a fresh machine at the plan to rebuild them.

### What execution revealed

- Chezmoi deploys the hook and its settings entry everywhere, but the skill and agent go nowhere automatically. A fresh machine gets a nudge that names a skill it does not have.
- The "rebuild from the plan" story is fragile. A1 shows the plan copy already drifted from the live file within hours.
- The two files are prose with frontmatter. Nothing about them is machine-specific or secret.

### Options

1. **Manage both under chezmoi.** Add `private_dot_claude/skills/cross-model-review/SKILL.md` and `private_dot_claude/agents/cross-model-reviewer.md` to the source tree. Delete the doctor's two `present` checks (A6 becomes moot) and update the README sentence that says they are hand-managed. Render tests assert the two files land. Cost: the first apply on this machine would offer to overwrite the live files; `chezmoi add` from the live copies first, then the tree is in sync. This also changes the spec's "Loose user config" decision, so edit that decision and Known deviation 6.
2. **Keep hand-managed but copy the bodies into the spec.** Removes the dependency on the plan, which is a less stable document, but keeps the drift problem and the manual rebuild.
3. **Keep as is.** The doctor catches a missing file, and this is George's only machine today.

### Recommendation

Option 1. The reason for hand-managing was consistency with the other custom skills, but those skills do not have a chezmoi-deployed hook that depends on them. Here the hook and settings already cross machines, so the files they need should travel with them. The whole change is two files added to the source tree, two checks removed, a README sentence, and a spec edit.

If Option 1 is taken, the order is: `chezmoi add ~/.claude/skills/cross-model-review/SKILL.md ~/.claude/agents/cross-model-reviewer.md`, confirm the source paths, remove the doctor checks and their render assertions, update README and spec, run the suite, `chezmoi apply` the two new targets, run `dotfiles-doctor` and confirm the cross-model section still passes.

## Not covered here

The unrelated dotfiles drift on this machine (the October 4 apply never ran, `dotfiles-capture` is missing, the doctor reports 14 unrelated failures) is a separate catch-up, documented in the README's "Claude Code and Zed settings" section.
