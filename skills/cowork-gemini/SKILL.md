---
name: cowork-gemini
description: Delegate cowork work to Gemini Flash via the Anti-Gravity CLI (agy). Use ONLY when the user explicitly asks for Gemini or Anti-Gravity; otherwise cowork pairs Codex with Claude.
compatibility: Requires Bash, Git, jq, a SHA-256 utility, and authenticated Claude Code and Codex CLIs for the default peer pair. Gemini (agy) and GitHub Copilot CLI are optional peers.
---

# Gemini via Anti-Gravity CLI

Use Gemini Flash as the independent second model only when the user
explicitly asks for Gemini or Anti-Gravity. Without that request, keep the
default pairing and do not mention or invoke it.

## Invocation

Resolve this skill's real directory after following any symlink, then set
`COWORK_RUNTIME_DIR` to its sibling `../cowork-runtime/scripts` directory.

**Always go through `$COWORK_RUNTIME_DIR/invoke-peer-review.sh`. Never call `agy`
directly.** Every guard in that script exists because a hand-written call
failed in a way that looked like "Gemini is broken":

| Hand-written call | What happens |
| ----------------- | ------------ |
| no `--print-timeout` | `agy` defaults to 5 minutes and the run dies mid-answer |
| prompt describes the change instead of containing it | the peer cannot read the repo, narrates progress it is not making, and burns the whole window |
| prompt over ~128 KiB as an argument | the kernel refuses it: `Argument list too long` |
| review run inside the working tree | file writes are auto-allowed, so a "read-only" review can edit the repo |

```bash
"$COWORK_RUNTIME_DIR/invoke-peer-review.sh" agy auto \
  --effort medium --prompt-file /tmp/review-prompt.txt
```

- **Model.** Pass `auto` unless the user named an exact slug. `auto` resolves
  the newest Gemini Flash on the account at run time through
  `$COWORK_RUNTIME_DIR/resolve-model.sh --family gemini-flash --via agy --effort <effort>`,
  which reads the live `agy models` list. Never hard-code a generation: today's
  newest is not next month's. `COWORK_MODEL` wins over resolution when the user
  supplied an exact id. Announce the resolved slug at kickoff — the script
  prints it to stderr.
- **Effort.** `medium` by default, `high` for adversarial challenges.
- **Prompt.** Put everything the peer needs *in the prompt*: the diff, the plan,
  the relevant source. State plainly that it must answer from the text alone and
  run nothing. `cowork-route.sh` does this for review actions by embedding
  `git diff`; do the same for any prompt you build
  yourself. Use `--prompt-file` rather than a giant shell argument.
- **Size.** Prompts over 120 KB automatically go to `agy` on stdin as
  stream-json; over 1 MB the script refuses rather than truncating, because a
  silently trimmed diff produces a confident review of code that was never
  shown. Narrow the scope instead.
- **Isolation.** The script runs `agy --sandbox` from a scratch directory, so
  the peer starts with no working tree in front of it. Do not add
  `--dangerously-skip-permissions`. This is defence in depth, not a sandbox
  boundary: `agy`'s headless permission mode is `request-review`, which
  soft-denies shell commands but still exposes `write_to_file`, and an absolute
  path reaches outside the scratch directory. So keep the original rule — after
  every review run, confirm `git status --porcelain` is unchanged, and
  investigate any new modification before trusting the findings.
- **Auth.** If the CLI reports an authentication error, surface it verbatim and
  stop. `resolve-model.sh` prints `agy models`' own stderr rather than claiming
  the account has no Flash model. Headless runs use cached credentials from a
  prior interactive `agy` sign-in. Do not retry silently and do not fall back to
  another model.

## Reading the result

- The peer's report is advisory input, never acceptance. Verify each claim
  against the code before acting on it — a Flash model will state a confident
  finding about behaviour it inferred rather than read.
- A review that returns only narration ("I am waiting for…", "once the tests
  finish…") means the prompt did not contain the material. Fix the prompt and
  re-run; do not treat it as a model or CLI fault.

## Rules

- Reviews and plan challenges are read-only; Anti-Gravity sessions must not edit files.
- Material write work follows the same bounded discipline as the bundled
  `codex-build` skill: isolated
  worktree from the recorded source `HEAD`, prompt contract via temp file, and
  unchanged human gates.
- The initiating model verifies the diff and proof itself. Gemini's report is
  advisory input, never acceptance.
