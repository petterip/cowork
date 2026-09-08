---
name: cowork-gemini
description: Delegate cowork work to Gemini Flash via the Anti-Gravity CLI (agy). Use ONLY when the user explicitly asks for Gemini or Anti-Gravity; otherwise cowork pairs Codex with Claude.
---

# Gemini via Anti-Gravity CLI

Use Gemini Flash as the independent second model only when the user
explicitly asks for Gemini or Anti-Gravity. Without that request, keep the
default pairing and do not mention or invoke it.

## Invocation

- Anti-Gravity CLI (`agy`) is the Gemini path. The vendor-dead `gemini` CLI
  has been removed; never attempt to call it. Announce the resolved model at
  kickoff after asking `agy models` for the current account list.
- Live listing is `agy models`. Never hard-code a Gemini version. Resolve the latest Flash slug at runtime
  with
  `${CODEX_HOME:-$HOME/.codex}/cowork/plugins/cowork/scripts/resolve-model.sh --family gemini-flash --via agy --effort medium`
  (use `--effort high` for adversarial challenges). `COWORK_MODEL` overrides
  the resolved slug when the user supplied an exact id.
- Read-only review or plan challenge: store the prompt in a shell variable
  sourced from a temp file, then run
  `agy -p "$PROMPT" --model "$RESOLVED" --print-timeout 10m`.
  The response goes to stdout; diagnostics and errors go to stderr.
- Never pass `--dangerously-skip-permissions` for reviews. Headless default
  policy soft-denies shell commands, but workspace file writes are
  auto-allowed, so after every review run verify `git status --porcelain` is
  unchanged; investigate any new modification before trusting the findings.
- If the CLI reports `authentication required` or another auth error, surface
  it verbatim and stop. Headless runs use cached credentials from a prior
  interactive `agy` sign-in. Do not retry silently and do not fall back to
  another model.

## Rules

- Reviews and plan challenges are read-only; Anti-Gravity sessions must not edit files.
- Material write work follows the same bounded discipline as
  `${CODEX_HOME:-$HOME/.codex}/cowork/skills/codex-build/SKILL.md`: isolated
  worktree from the recorded source `HEAD`, prompt contract via temp file, and
  unchanged human gates.
- The initiating model verifies the diff and proof itself. Gemini's report is
  advisory input, never acceptance.
