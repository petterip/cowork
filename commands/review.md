---
description: Ask a second model to independently review the current Claude Code work
argument-hint: "[--base <ref>] [--gemini] [--copilot] [--model <slug>] [focus]"
allowed-tools: Bash(*cowork-route.sh:*)
---

Review the current code or diff, not an implementation plan.

Run `$CLAUDE_PLUGIN_ROOT/skills/cowork-runtime/scripts/cowork-route.sh review "$ARGUMENTS"`. When the
arguments contain review focus text beyond routing flags, or explicitly
challenge a design, assumption, or risk, use action `adversarial-review`
instead because the official normal review accepts no custom focus. The router
uses the official plugin runtime when available and the local `codex review`
fallback otherwise. Include `--gemini` only when the user explicitly asks for
Gemini; the router then uses Antigravity (`agy`) and resolves the current
Gemini Flash slug from `agy models`. Include `--copilot` only when the user
explicitly asks for GitHub Copilot CLI. Combine `--gemini --copilot` to resolve
Gemini Flash from Copilot's live model list. Pass `--model` only for an exact
slug; do not invent a version.

Return findings without modifying files. The author model decides and applies
fixes only after presenting the review.
