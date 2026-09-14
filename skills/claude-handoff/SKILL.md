---
name: claude-handoff
description: "Use only when cowork-continue selects a fresh Claude background session, or when claude-handoff is explicitly requested by name. General requests to move work to another model enter through cowork-continue for host-aware routing."
compatibility: Requires Bash, Git, jq, a SHA-256 utility, and authenticated Claude Code and Codex CLIs for the default peer pair. Gemini (agy) and GitHub Copilot CLI are optional peers.
---

Write a handoff summary of the current conversation so a fresh agent can continue the work. Resolve `COWORK_RUNTIME_DIR` to `../cowork-runtime/scripts` and `RALLY_SCRIPTS` to `../codex-claude-rally/scripts` relative to this skill's real base directory after following any symlink. Before writing the summary, run `"$COWORK_RUNTIME_DIR/require-peer-egress.sh" claude`, then run `"$RALLY_SCRIPTS/assert-subscription-auth.sh"`. If either fails, do not launch Claude or change credentials; report the blocker.

Resolve access before launch: `ACCESS_ARGS=(); if [[ "$("$RALLY_SCRIPTS/detect-full-access.sh")" == full ]]; then ACCESS_ARGS=(--dangerously-skip-permissions); fi`. Launch a background agent seeded with the summary: `claude --bg "${ACCESS_ARGS[@]}" --name "<descriptive name>" "<handoff summary>"`. Full access is mandatory when the user authorized it or Codex already uses danger-full-access; otherwise preserve Claude's default permission mode. It starts in the current working directory and returns immediately; manage it with `claude agents`.

Always pass `-n`/`--name` with a descriptive name. Include a "suggested skills" section in the summary, reference existing PRDs, plans, ADRs, issues, commits, and diffs instead of duplicating them, and redact secrets or personally identifiable information.

If the user passed arguments, use them to tailor the next session's focus.
