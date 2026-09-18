---
description: Build a human-approved frozen plan with Codex and independently verify it
argument-hint: '[plan path]'
---

First read `$CLAUDE_PLUGIN_ROOT/skills/codex-claude-rally/references/delegation.md`.
Honor the user’s per-phase provider/model choices through that provider’s skill;
the Codex route below is the default when unspecified.

Read and run `$CLAUDE_PLUGIN_ROOT/skills/codex-build/SKILL.md` for `$ARGUMENTS`.
This is the verified build path. The official `/codex:rescue` command is for
unstructured investigation and must not replace the frozen-spec, proof, and
human-approval gates.
