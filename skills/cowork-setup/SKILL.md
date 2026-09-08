---
name: cowork-setup
description: Verify that Cowork prerequisites, authentication, full-access inheritance, and artifact storage are ready. Use before the first Cowork job or when delegation fails.
---

# Setup

Run `${CODEX_HOME:-$HOME/.codex}/cowork/skills/codex-claude-rally/scripts/verify-environment.sh` and report its exact
result. Do not change credentials. A failed required check blocks Claude or
Codex delegation; restricted full-access status is informational unless the
user already authorized full access. Gemini (`agy`) and GitHub Copilot CLI
(`copilot`) are optional until requested. If Claude plugin list still shows
`cowork@cowork-claude-codex`, report that the shipped id is `cowork@cowork`
and do not uninstall or install without the user's request.
