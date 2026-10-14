# graphify
- **graphify** (`~/.claude/skills/graphify/SKILL.md`) - any input to knowledge graph. Trigger: `/graphify`
When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

# Status footer
Add a short footer only after longer stretches of work, when the user has likely tabbed away: roughly 10+ tool calls, subagents or long-running commands, or a multi-step task finishing. Skip it for quick back-and-forth, answers to questions, and small edits; the status line already shows the session's context. Format:
**Goal:** <the original request, one line> · **Done:** <what this turn accomplished> · **Next:** <what's pending, or what you need from the user>

# Progress narration
- Before each group of tool calls, write one short sentence saying what you're about to do and why (e.g. "Checking how auth tokens are refreshed before changing the retry logic."). Skip it for trivial follow-ups.
- For work with 3+ steps, keep a task list and mark items in progress/complete as you go, so the current step is always visible.
- When a finding changes the plan, say so in one line as it happens rather than only in the final summary.
- Give every Bash call a clear plain-English description; it's shown to the user as the current activity.

# Todos for George
`~/TODO.md` is George's personal todo inbox. Write to it only in two cases:
- George explicitly asks you to add a todo ("add a todo", "note that for me", "remind me to").
- George explicitly asks for next steps. Answer in chat as usual, and also append each step as its own line.
Append one line per item to the end of the file with the Edit or Write tool, not a shell redirect (the permission rule in settings covers those tools): `- [ ] YYYY-MM-DD · <project dir name> · <text>`. If the file is missing, create it with a `# TODO` header first. Append only: never check off, reorder, edit, or delete existing lines. After writing, echo the line(s) you added. The status footer's "Next:" line does not count as a next-steps request.

# Coding guidelines
These bias toward caution over speed. For trivial tasks, use judgment.

## Think before coding
Don't assume. Don't hide confusion. Surface tradeoffs. Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them; don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.
- Ask questions one at a time, and wait for the answer before asking the next. This applies to AskUserQuestion too: one question per call.

## Simplicity first
Minimum code that solves the problem. Nothing speculative.
- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it. Ask: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## Surgical changes
Touch only what you must. Clean up only your own mess. When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it; don't delete it.
- Remove imports, variables, and functions that your changes made unused. Don't remove pre-existing dead code unless asked.

The test: every changed line should trace directly to the user's request.

## Goal-driven execution
Define success criteria. Loop until verified. Turn tasks into verifiable goals:
- "Add validation" → write tests for invalid inputs, then make them pass.
- "Fix the bug" → write a test that reproduces it, then make it pass.
- "Refactor X" → ensure tests pass before and after.

For multi-step tasks, state a brief plan where each step names its check:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
```
Strong success criteria let you loop independently. Weak ones ("make it work") require constant clarification.
