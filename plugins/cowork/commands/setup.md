---
description: Check Cowork and its optional Codex, Gemini, and Copilot peers
allowed-tools: Bash(claude plugin:*), Bash(*verify-environment.sh)
---

Run `$CLAUDE_PLUGIN_ROOT/workflows/codex-claude-rally/scripts/verify-environment.sh`
and report its exact result. Run `claude plugin list` and report whether
`codex@openai-codex` is enabled.

The official Codex plugin is optional. When absent, state that Cowork's local
Codex CLI fallback remains available. Gemini (`agy`) and GitHub Copilot CLI
(`copilot`) are optional until the user asks for those peers. Never install or
change authentication without the user's request.
