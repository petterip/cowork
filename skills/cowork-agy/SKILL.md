---
name: cowork-agy
metadata:
  version: 1.6.0
description: Delegate cowork work through the Anti-Gravity CLI (agy). Use only when the user explicitly asks for that peer; otherwise preserve the default pairing.
---

# Anti-Gravity CLI

Follow [the shared delegation contract](../codex-claude-rally/references/delegation.md) from this skill’s resolved directory (follow symlinks). Named agents are defaults; explicit choices use the selected provider’s workflow.

Use this independent peer only when the user explicitly asks for it. Without
that request, keep the default pairing and do not mention or invoke it.

## Invocation

Resolve `RALLY_SCRIPTS` to `../codex-claude-rally/scripts` from this skill's
real directory, then run
`COWORK_PLUGIN_ROOT=$("$RALLY_SCRIPTS/resolve-cowork-root.sh")`.

**For reviews, go through `scripts/invoke-peer-review.sh`.** Every guard in that script exists because a hand-written call
failed in a way that looked like "the peer is broken":

| Hand-written call | What happens |
| ----------------- | ------------ |
| no `--print-timeout` | `agy` defaults to 5 minutes and the run dies mid-answer |
| prompt describes the change instead of containing it | the peer cannot read the repo, narrates progress it is not making, and burns the whole window |
| prompt over ~128 KiB as an argument | the kernel refuses it: `Argument list too long` |
| review run inside the working tree | file writes are auto-allowed, so a "read-only" review can edit the repo |

```bash
"$COWORK_PLUGIN_ROOT/scripts/invoke-peer-review.sh" agy auto \
  --prompt-file /tmp/review-prompt.txt
```

- **Model.** Pass `auto` when the user supplied no model, which omits the model
  option and uses the peer's native default. Resolve supplied text through
  `scripts/cowork resolve --peer agy`; never embed model names in this skill.
- **Effort.** Pass an effort only when the user or workflow requested it.
- **Prompt.** Put everything the peer needs *in the prompt*: the diff, the plan,
  the relevant source. State plainly that it must answer from the text alone and
  run nothing. `cowork-route.sh` does this for review actions by embedding
  the tracked diff and untracked file contents; do the same for any prompt you build
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
  stop. Headless runs use cached credentials from a
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
- For builds and continuation, follow [the peer work workflow](../codex-claude-rally/references/peer-work.md)
  and use `scripts/invoke-peer-work.sh` with provider `agy`.
- The initiating model verifies the diff and proof itself. The peer's report is
  advisory input, never acceptance.
