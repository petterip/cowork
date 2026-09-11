---
name: cowork-plan
description: Plan work in Codex and use an independent second model. Use when requirements need clarification, an implementation plan needs challenge, or documentation-aware planning is requested before code.
---

# Plan

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
