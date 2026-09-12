---
description: Ask a second model to independently review the current Claude Code work
argument-hint: "[--base <ref>] [--codex|--gemini|--copilot] [--model <slug>|--model-family <name>] [--effort <level>] [focus]"
allowed-tools: Bash(*cowork-route.sh:*)
---

Review the current code or diff, not an implementation plan.

Run `$CLAUDE_PLUGIN_ROOT/scripts/cowork-route.sh review "$ARGUMENTS"`. When the
arguments contain review focus text beyond routing flags, or explicitly
challenge a design, assumption, or risk, use action `adversarial-review`
instead because the official normal review accepts no custom focus. The router
uses the official plugin runtime when available and the local `codex review`
fallback otherwise. Include `--gemini` only when the user explicitly asks for
Gemini; the router then uses Antigravity (`agy`) and resolves the current
Gemini Flash slug from `agy models`. Include `--copilot` only when the user
explicitly asks for GitHub Copilot CLI. Combine `--gemini --copilot` to resolve
Gemini Flash from Copilot's live model list. Pass `--model` only for an exact
slug; do not invent a version. Include `--codex` when the user explicitly asks
for Codex with a named model or reasoning effort. Pass `--effort` only when the
user requested it; the router must enforce it on the selected peer invocation,
not merely mention it in the prompt or status output. For a family name without
an exact slug, pass `--model-family <name>`; the router resolves the newest
matching id from the selected peer's live model catalog. Model family and
effort values are not a built-in allowlist: pass safe names through and let the
selected peer's current catalog and CLI validate support.

Return findings without modifying files. The author model decides and applies
fixes only after presenting the review.
