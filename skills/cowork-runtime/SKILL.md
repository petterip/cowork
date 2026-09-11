---
name: cowork-runtime
description: Use only when another Cowork skill directs you to run Cowork's bundled routing, peer-review, or model-resolution scripts. Do not select this internal support skill for user requests; use the matching cowork-plan, cowork-build, cowork-review, cowork-continue, cowork-status, or cowork-setup skill instead.
compatibility: Requires Bash and Git. Peer review additionally requires Codex, Claude Code, Antigravity, or GitHub Copilot CLI as selected by the calling Cowork skill.
---

# Cowork Runtime

This is an internal support skill. Follow the user-facing Cowork skill that
loaded it; do not create a separate workflow from this file.

Bundled scripts:

- `scripts/cowork-route.sh --help` routes review, transfer, and status actions.
- `scripts/invoke-peer-review.sh --help` runs a bounded Gemini or Copilot review.
- `scripts/resolve-model.sh --help` resolves current peer model identifiers.

Invoke scripts through paths relative to this skill directory. Preserve their
exit status and surface stderr when a command fails.
