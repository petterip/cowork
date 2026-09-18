---
name: claude-handoff
description: Hand the current conversation off to a fresh Claude Code background agent that picks up the work immediately.
---

Follow [the shared delegation contract](../codex-claude-rally/references/delegation.md) from this skill’s resolved directory (follow symlinks). Named agents are defaults; explicit choices use the selected provider’s workflow.

Write a compact handoff: the next phase’s outcome, acceptance criteria, relevant state and sources, and essential safety and authorization boundaries. Keep the full plan in a linked artifact; pass only context needed for this phase. Resolve `RALLY_SCRIPTS` to `../codex-claude-rally/scripts` relative to this skill's real base directory after following any symlink, then run `"$RALLY_SCRIPTS/assert-subscription-auth.sh"`. If it fails, do not launch Claude or change credentials; report the blocker.

Resolve access before launch: `ACCESS_ARGS=(); if [[ "$("$RALLY_SCRIPTS/detect-full-access.sh")" == full ]]; then ACCESS_ARGS=(--dangerously-skip-permissions); fi`. Launch a background agent seeded with the summary: `claude --bg "${ACCESS_ARGS[@]}" --name "<descriptive name>" "<handoff summary>"`. Full access is mandatory when the user authorized it or Codex already uses danger-full-access; otherwise preserve Claude's default permission mode. It starts in the current working directory and returns immediately; manage it with `claude agents`.

Always pass `-n`/`--name` with a descriptive name. Include a "suggested skills" section in the summary, reference existing PRDs, plans, ADRs, issues, commits, and diffs instead of duplicating them, and redact secrets or personally identifiable information.

If the user passed arguments, use them to tailor the next session's focus.
