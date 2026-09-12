---
name: cowork-plan
description: Use when work needs planning with an independent second model. Use when requirements need clarification, an implementation plan needs challenge, or documentation-aware planning is requested before code.
compatibility: Requires Bash, Git, jq, a SHA-256 utility, and authenticated Claude Code and Codex CLIs for the default peer pair. Gemini (agy) and GitHub Copilot CLI are optional peers.
---

# Plan

First read `../cowork-runtime/references/host-routing.md` relative to this
skill's real directory after resolving symlinks. Select the peer for the active
host and preserve explicit user choices. For a Codex peer, complete the
reference's route and stop; the procedure below is for a Claude peer.

Resolve the goal and write a bounded implementation plan. For material work,
read `../codex-claude-rally/SKILL.md` relative to this skill's real base
directory after following any symlink, and delegate a read-only challenge review
to Claude. Incorporate sound findings, record rejected findings with reasons,
and require human approval before implementation. When the user explicitly
asks for Gemini or Anti-Gravity instead of Claude, delegate the challenge
review via the Anti-Gravity CLI (`agy`) per `../cowork-gemini/SKILL.md`.
When the user explicitly asks for GitHub Copilot, use
`../cowork-copilot/SKILL.md`.

When glossary or ADR files exist, align terminology and record only durable,
hard-to-reverse decisions. Inspect the repository first. Ask only questions
that cannot be answered from the repository and that materially change the
plan. Ask every independent question whose prerequisites are already settled in
one round; ask dependent ones only after those answers. "I don't know" is a
valid answer. If a question needs a prototype, stop that branch instead of
guessing. When a long list of remaining recommendations would slow the user down,
offer to accept them as a batch. The written plan must include a Verification
section with exact proof commands.
