---
description: Resolve what to build and produce a cross-model-reviewed implementation plan
argument-hint: '[--docs] [existing plan path] [task]'
---

First read `$CLAUDE_PLUGIN_ROOT/skills/codex-claude-rally/references/delegation.md`.
Keep the planning workflow below; use the user’s selected provider/model only
for its delegated review step. Codex is the reviewer default.

Choose one canonical workflow:

1. Existing plan path or explicit plan-review request: read and run
   `$CLAUDE_PLUGIN_ROOT/skills/codex-review/SKILL.md`.
2. `--docs`, `CONTEXT.md`, or relevant ADRs: read and run
   `$CLAUDE_PLUGIN_ROOT/skills/grill-with-docs-codex/SKILL.md`.
3. Otherwise: read and run
   `$CLAUDE_PLUGIN_ROOT/skills/grill-me-codex/SKILL.md`.

Pass `$ARGUMENTS` through. Call the activity collaborative planning. Ask only
decision-changing questions, write no production code before human approval,
and preserve the bounded cross-model review.
