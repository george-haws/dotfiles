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
