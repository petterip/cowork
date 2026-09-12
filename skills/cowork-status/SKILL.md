---
name: cowork-status
description: Show active and recent Cowork jobs and workers for the current repository. Use when the user asks what cross-model work is running, finished, blocked, or resumable.
compatibility: Requires Bash, Git, jq, a SHA-256 utility, and authenticated Claude Code and Codex CLIs for the default peer pair. Gemini (agy) and GitHub Copilot CLI are optional peers.
---

# Status

First read `../cowork-runtime/references/host-routing.md` relative to this
skill's real directory after resolving symlinks. Include its available official
Codex status source alongside the sources below; mark unavailable sources.

Read Rally manifests under
`${XDG_STATE_HOME:-$HOME/.local/state}/cowork/jobs` and the legacy directory
`${XDG_STATE_HOME:-$HOME/.local/state}/cowork-claude-codex/jobs`, and, when Claude CLI is available, query
`claude agents --cwd "$PWD" --all --json`. Filter by a requested job ID when supplied. Present one compact table with job,
direction, state, owner, round, worker, and next action. Do not mutate jobs.
Include only manifests whose `repository_path` equals
`git rev-parse --show-toplevel`, unless the user explicitly requests all repos.
