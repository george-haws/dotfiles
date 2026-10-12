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
3. **Different family.** The reported model's family differs from yours: fable versus opus. Compare families, not strings; the reviewer may name itself with an alias or a full model ID. `Reviewer model: unknown` fails this check. As of Claude Code 2.1, the Agent tool result carries no model field (only agent id, token count, tool uses, and duration), so this self-reported line is the only automatic check; the `/tasks` view shows the model that actually ran and is the manual confirmation. George can confirm the real model in the `/tasks` view.
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
