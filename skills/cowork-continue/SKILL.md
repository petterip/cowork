---
name: cowork-continue
description: Continue the current Codex work in a fresh second-model session. Use when the user wants the other model to take over the current task with its decisions and remaining work intact.
---

# Continue

Follow [the shared delegation contract](../codex-claude-rally/references/delegation.md) from this skill’s resolved directory (follow symlinks). Named agents are defaults; explicit choices use the selected provider’s workflow.

Read and follow `../claude-handoff/SKILL.md` relative to this skill's real base
directory after following any symlink. Produce a compact handoff with
goal, current state, decisions, artifacts, remaining work, proof, and the
user's requested focus. Start Claude in the current repository and inherit full
access when already authorized. For an explicitly selected Gemini or Copilot continuation,
follow `../cowork-gemini/SKILL.md` or `../cowork-copilot/SKILL.md` and use the
peer work launcher with the handoff and current worker/repository path.
