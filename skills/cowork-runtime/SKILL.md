---
name: cowork-runtime
description: Use only when another Cowork skill directs you to run Cowork's bundled routing, peer-review, or model-resolution scripts. Do not select this internal support skill for user requests; use the matching cowork-plan, cowork-build, cowork-review, cowork-continue, cowork-status, or cowork-setup skill instead.
compatibility: Requires Bash and Git. Peer review additionally requires Codex, Claude Code, Antigravity, or GitHub Copilot CLI as selected by the calling Cowork skill.
---

# Cowork Runtime

This is an internal support skill. Follow the user-facing Cowork skill that
loaded it; do not create a separate workflow from this file.

For host and peer selection by a public Cowork action, read
`references/host-routing.md`.

Bundled scripts:

- `scripts/cowork-route.sh --help` routes review, transfer, and status actions.
- `scripts/invoke-peer-review.sh --help` runs a bounded Gemini or Copilot review.
- `scripts/require-peer-egress.sh <destination>` blocks peer launch unless the
  payload classification and approved destination are explicit. Confidential
  or restricted payloads also require confirmed scope reduction.
- `scripts/resolve-model.sh --help` resolves current peer model identifiers.

Invoke scripts through paths relative to this skill directory. Preserve their
exit status and surface stderr when a command fails.

Before a peer launch, export `COWORK_DATA_CLASSIFICATION` and the comma-separated,
space-free `COWORK_APPROVED_DESTINATIONS`. Routes use `claude`, `codex`, `agy` for
`--gemini`, and `copilot` for `--copilot`. Export
`COWORK_REDACTION_CONFIRMED=true` for confidential or restricted payloads.
Status is local inspection and does not require the gate.
