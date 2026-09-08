---
name: cowork-continue
description: Continue the current Codex work in a fresh Claude Code background session. Use when the user wants the other model to take over the current task with its decisions and remaining work intact.
---

# Continue

Read and follow `${CODEX_HOME:-$HOME/.codex}/cowork/skills/claude-handoff/SKILL.md`. Produce a compact handoff with
goal, current state, decisions, artifacts, remaining work, proof, and the
user's requested focus. Start Claude in the current repository and inherit full
access when already authorized. When the user explicitly asks to continue in Gemini or Anti-Gravity, hand off
to an `agy` (Anti-Gravity CLI) session per
`${CODEX_HOME:-$HOME/.codex}/cowork/skills/cowork-gemini/SKILL.md` instead.
