---
description: Continue the current Claude Code work in Codex
argument-hint: '[focus]'
allowed-tools: Bash(*cowork-route.sh:*), Bash(*invoke-peer-work.sh:*), Bash(*resolve-model.sh:*), Bash(codex exec:*)
---

First read `$CLAUDE_PLUGIN_ROOT/skills/codex-claude-rally/references/delegation.md`.
Honor the user’s per-phase provider/model choices through that provider’s skill;
the Codex route below is the default when unspecified. For Gemini or Copilot,
use the peer work launcher from its skill instead of the Codex transfer router.

For Codex/default only, run `$CLAUDE_PLUGIN_ROOT/scripts/cowork-route.sh transfer "$ARGUMENTS"`. A zero
exit means the official plugin created a resumable Codex thread.

On that Codex route’s exit 2, compact the current work into a handoff containing the goal, current
state, decisions, referenced artifacts, remaining work, proof, and `$ARGUMENTS`.
Start a fresh Codex session with that handoff, inherit full access when already
authorized, capture its explicit thread ID, and return the exact
`codex resume <thread-id>` command. Do not edit project files during transfer.
