---
description: Ask a second model to independently review the current Claude Code work
argument-hint: "[--base <ref>] [--peer <name>] [--model <id>|--model-name <text>] [--effort <level>] [focus]"
allowed-tools: Bash(*cowork-route.sh:*)
---

Follow `$CLAUDE_PLUGIN_ROOT/skills/codex-claude-rally/references/delegation.md`
for the task scope and per-phase provider/model choice before routing.

Review the current code or diff, not an implementation plan.

Run `$CLAUDE_PLUGIN_ROOT/scripts/cowork-route.sh review "$ARGUMENTS"`. When the
arguments contain review focus text beyond routing flags, or explicitly
challenge a design, assumption, or risk, use action `adversarial-review`
instead because the official normal review accepts no custom focus. The router
uses the official plugin runtime when available and the local `codex review`
fallback otherwise. Include `--peer` only when the user explicitly selects a
peer. Pass `--model` when the user supplies an exact id and
`--model-name` for other model text; both are resolved against the selected
peer's cached live catalog. Do not invent a name or version. Pass `--effort`
only when the user requested it; the router must enforce it on the selected
peer invocation, not merely mention it in the prompt or status output.

Return findings without modifying files. The author model decides and applies
fixes only after presenting the review.
