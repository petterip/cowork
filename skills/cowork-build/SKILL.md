---
name: cowork-build
description: Build a frozen plan by delegating implementation to a second model and independently verifying the result. Use for bounded multi-file implementation where one model writes and another reviews.
compatibility: Requires Bash, Git, jq, a SHA-256 utility, and authenticated Claude Code and Codex CLIs for the default peer pair. Gemini (agy) and GitHub Copilot CLI are optional peers.
---

# Build

First read `../cowork-runtime/references/host-routing.md` relative to this
skill's real directory after resolving symlinks. Select the peer for the active
host and preserve explicit user choices. For a Codex peer, complete the
reference's route and stop; the procedure below is for a Claude peer.

Freeze the implementation plan from the user's request and available source
artifacts without requiring separate human approval. The source checkout may
contain staged, unstaged, or untracked user work: record it, leave it untouched,
and create the isolated Claude worktree from the recorded `HEAD` commit so none
of those local changes enter the worker. Require exact allowed paths and a proof
command. Pass the task repository explicitly with `--repo`. Read `../codex-claude-rally/SKILL.md` relative to this skill's real
base directory after following any symlink, and create a write job in an
isolated Claude worktree. The initiating host must inspect the complete scoped diff and run
proof independently before asking the user whether to apply or commit it. At
hand-back, never overwrite local work: apply-check against the source checkout
and surface an overlap for user resolution. When the user explicitly asks for
Gemini or Anti-Gravity as the builder, run it via the Anti-Gravity CLI (`agy`)
following `../cowork-gemini/SKILL.md` with the
same worktree, proof, and hand-back rules. When the user explicitly asks for
GitHub Copilot as the builder, follow `../cowork-copilot/SKILL.md`.
