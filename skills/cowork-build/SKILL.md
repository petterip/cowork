---
name: cowork-build
description: Build a frozen plan by delegating implementation to a second model and independently verifying the result. Use for bounded multi-file implementation where one model writes and another reviews.
---

# Build

Freeze the implementation plan from the user's request and available source
artifacts without requiring separate human approval. The source checkout may
contain staged, unstaged, or untracked user work: record it, leave it untouched,
and create the isolated Claude worktree from the recorded `HEAD` commit so none
of those local changes enter the worker. Require exact allowed paths and a proof
command. Read
`${CODEX_HOME:-$HOME/.codex}/cowork/skills/codex-claude-rally/SKILL.md` and create a write job in an
isolated Claude worktree. Codex must inspect the complete scoped diff and run
proof independently before asking the user whether to apply or commit it. At
hand-back, never overwrite local work: apply-check against the source checkout
and surface an overlap for user resolution. When the user explicitly asks for
Gemini or Anti-Gravity as the builder, run it via the Anti-Gravity CLI (`agy`)
following
`${CODEX_HOME:-$HOME/.codex}/cowork/skills/cowork-gemini/SKILL.md` with the
same worktree, proof, and hand-back rules. When the user explicitly asks for
GitHub Copilot as the builder, follow
`${CODEX_HOME:-$HOME/.codex}/cowork/skills/cowork-copilot/SKILL.md`.
