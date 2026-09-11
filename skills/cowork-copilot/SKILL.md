---
name: cowork-copilot
description: Delegate cowork work to GitHub Copilot CLI. Use ONLY when the user explicitly asks for Copilot; otherwise cowork pairs Codex with Claude.
---

# GitHub Copilot CLI

Use the GitHub Copilot CLI (`copilot` from `@github/copilot`) as a peer only
when the user explicitly asks for Copilot. The older `gh copilot` extension
is a different tool and is not this path.

## Invocation

Resolve `COWORK_PLUGIN_ROOT` to the plugin root two directories above this
skill's real base directory after following any symlink.

- Non-interactive reviews use `copilot -p` with `-s` and `--no-ask-user`.
  Allow only `git status`, `git diff`, `git log`, and `git show`. Do not pass
  `--allow-all`, `--yolo`, or `shell(git:*)`.
- Never hard-code a model version. For Copilot's own picker, resolve with
  `$COWORK_PLUGIN_ROOT/scripts/resolve-model.sh --family auto --via copilot`,
  or simply pass `auto` to `scripts/invoke-peer-review.sh`, which resolves it
  (prints `auto`). For Gemini Flash through Copilot, use
  `--family gemini-flash --via copilot`. `COWORK_MODEL` or `--model` supplies
  an exact slug when the user named one.
- Live listing is best-effort: try `copilot /model --list --json`, then
  `copilot --help`. If neither yields ids, stop and ask for `--model`. Do
  not invent a slug.
- After a read-only run, verify `git status --porcelain` is unchanged.

## Build

Material write work follows the bundled `codex-build` skill's isolated
worktree and human gates. Reviews
stay read-only; do not reuse the review allow-list for a builder.

## Rules

- Reviews and plan challenges are read-only; Copilot must not edit files.
- The initiating model verifies the diff and proof itself. Copilot's report
  is advisory input, never acceptance.
