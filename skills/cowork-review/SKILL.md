---
name: cowork-review
description: Ask a second model to independently review the current Codex work. Use for code, diff, design, security, or regression review when a second model should challenge completed or in-progress changes without editing them.
---

# Review

Read `${CODEX_HOME:-$HOME/.codex}/cowork/skills/codex-claude-rally/SKILL.md` and create a read-only Claude review job.
Resolve the reviewed repository root from the user's task workspace and pass it
explicitly with `--repo`; never create the job from the Cowork skill directory
without that target. Give the exact base/diff scope and review focus. In
read-only mode, allowed paths are review targets and declared source-of-truth
files remain readable. Claude must not edit. Codex reads the immutable response,
verifies every finding against source, and owns all subsequent fixes.

When the user explicitly asks for Gemini or Anti-Gravity, run the read-only
review via the Anti-Gravity CLI (`agy`) per
`${CODEX_HOME:-$HOME/.codex}/cowork/skills/cowork-gemini/SKILL.md` instead of
creating a rally job. When the user explicitly asks for GitHub Copilot, use
`${CODEX_HOME:-$HOME/.codex}/cowork/skills/cowork-copilot/SKILL.md`.

## Resolving a requested model to a peer

Requests name _models_; peers are _CLIs_, and the two layers never share a
name. Astra is an OpenAI model served by the Codex peer (`codex -m <slug>`, or
the configured default in Codex config); Opus and Fable are Claude models
served by the rally worker (`claude --model fable`); Gemini Flash resolves
live from `agy models`; Copilot-hosted models from `copilot /model --list
--json`. A requested model name is a slug-resolution question about the
underlying peer CLI, never a `which <model-name>` probe: do not report a model
missing because no binary carries its name. Codex has no model-list command —
its configured default is the authority, and a slug is only validated by the
backend on a real request, not by the CLI parser (an account may accept the
default while rejecting sibling slugs). Resolve the exact slug from the peer's
own surface rather than guessing a version string.

Opus and Fable resolve to exactly one peer: the local Claude Code rally worker
(`claude --model opus`), launched in `repository_path`. This skill has no cloud
Claude peer. `claude --cloud` and `claude --environment` start an
Anthropic-hosted session against a remote snapshot, so they cannot see the local
uncommitted worktree a review targets, and no other vendor's cloud, remote, or
subagent mode may stand in for the Claude peer. If the user says "Cloud Opus",
ask once which they mean: local `claude --model opus` in `repository_path`, or
an explicit remote-snapshot session that reviews committed `HEAD` only.
