---
name: cowork-continue
description: Continue the current Codex work in a fresh second-model session. Use when the user wants the other model to take over the current task with its decisions and remaining work intact.
---

# Continue

Read and follow `../claude-handoff/SKILL.md` relative to this skill's real base
directory after following any symlink. Produce a compact handoff with
goal, current state, decisions, artifacts, remaining work, proof, and the
user's requested focus. Start Claude in the current repository and inherit full
access when already authorized. When the user explicitly asks to continue in Gemini or Anti-Gravity, hand off
to an `agy` (Anti-Gravity CLI) session per `../cowork-gemini/SKILL.md`
instead. When the user explicitly asks for GitHub Copilot, follow the bundled
`../cowork-copilot/SKILL.md`.
