---
name: cowork-build
description: Build a frozen plan by delegating implementation to a second model and independently verifying the result. Use for bounded multi-file implementation where one model writes and another reviews.
---

# Build

Follow [the shared delegation contract](../codex-claude-rally/references/delegation.md) from this skill’s resolved directory (follow symlinks). Named agents are defaults; explicit choices use the selected provider’s workflow.

Freeze the implementation plan from the user's request and available source
artifacts without requiring separate human approval. The source checkout may
contain staged, unstaged, or untracked user work: record it, leave it untouched,
and create the isolated Claude worktree from the recorded `HEAD` commit so none
of those local changes enter the worker. Require exact allowed paths and a proof
command. Read `../codex-claude-rally/SKILL.md` relative to this skill's real
base directory after following any symlink, and create a write job in an
isolated Claude worktree. Codex must inspect the complete scoped diff and run
proof independently before asking the user whether to apply or commit it. At
hand-back, never overwrite local work: apply-check against the source checkout
and surface an overlap for user resolution. For an explicitly selected Gemini or Copilot builder, follow
`../cowork-gemini/SKILL.md` or `../cowork-copilot/SKILL.md` and use their shared
peer work launcher in the same isolated worktree, with independent proof.
