---
name: cowork-review
description: Ask a second model to independently review the current Codex work. Use for code, diff, design, security, or regression review when a second model should challenge completed or in-progress changes without editing them.
---

# Review

Read `../codex-claude-rally/SKILL.md` relative to this skill's real base
directory after following any symlink, and create a read-only Claude review job.
Resolve the reviewed repository root from the user's task workspace and pass it
explicitly with `--repo`; never create the job from the Cowork skill directory
without that target. Give the exact base/diff scope and review focus. In
read-only mode, allowed paths are review targets and declared source-of-truth
files remain readable. Claude must not edit. The initiating model (Codex or
GitHub Copilot CLI, whichever invoked this skill) reads the immutable response,
verifies every finding against source, and owns all subsequent fixes.

For uncommitted-work review, `create-rally-job.sh` automatically records the
current `HEAD` as the manifest `base_commit`; tell the worker to review the
working tree against that `HEAD`, including staged, unstaged, and untracked
changes. Enumerate the changed paths yourself before creating the job: combine
`git diff --name-only HEAD` (tracked changes against `HEAD`, staged and
unstaged) with `git ls-files --others --exclude-standard` (untracked files),
dedupe the combined list, and pass those paths as `allowed_paths`. List
relevant unchanged tests, schemas, or contracts in the request as readable
source-of-truth files that stay unchanged. Use `--proof-command 'none'` for
the read-only job itself unless the user supplied an exact proof command. The
initiating model decides which focused proof to run while independently
verifying the findings.

When the user explicitly asks for Gemini or Anti-Gravity, run the read-only
review via the Anti-Gravity CLI (`agy`) per `../cowork-gemini/SKILL.md`
instead of creating a rally job. When the user explicitly asks for GitHub
Copilot, use `../cowork-copilot/SKILL.md`. When the user explicitly asks for
Codex from another host, use the local `codex review` path.

## Resolving a requested model to a peer

Requests name _models_; peers are _CLIs_, and the two layers never share a
name. Resolve the route in this order:

1. **Explicit peer wins.** In "with Copilot Opus", Copilot is the peer and Opus
   is a model query against Copilot's live catalog. In "via Codex Terra low",
   Codex is the peer, Terra is a Codex model query, and low is that invocation's
   reasoning effort. Never redirect an explicitly named peer because the same
   model family is commonly associated with another CLI.
2. **Otherwise infer from an unqualified model.** Known Claude aliases use the
   local Claude rally worker, known GPT/OpenAI families use Codex, and Gemini
   Flash uses `agy`. For a family not known when this skill was written, query
   the available peers' live catalogs. Use the peer only when exactly one
   catalog reports a match; if none or multiple do, require an explicit peer
   instead of guessing. A bare Copilot request uses Copilot's `auto` model.

Resolve a named model from the selected peer's own surface: local Claude aliases
for Claude, `codex debug models` for Codex, `agy models` for Gemini, and the
`model` list from `copilot help config` for Copilot. For Copilot or Codex, pass the
user's family/name to `cowork-route.sh` as `--model-family <name>`; the router
selects the newest matching reported id, including families published after
this skill. If there is no match, stop instead of inventing a version. A live
`--model-family` request outranks an ambient
`COWORK_MODEL`; use `--model <exact-slug>` when the user explicitly supplies
the full id. A requested reasoning effort is also peer data: pass its safe
level name through unchanged and let the selected CLI validate whether that
version supports it. Codex receives `-c model_reasoning_effort=<level>`,
Copilot receives `--effort <level>`, and Claude/Gemini follow their
peer-specific surfaces. Do not print an effort in status output unless the
invocation actually enforces it.

The `codex review` subcommand is the read-only Codex review surface. It receives
the selected `-m` and `-c model_reasoning_effort=...` options before `review`;
it must not be replaced with a general write-capable `codex exec` session.

An unqualified known Claude alias resolves to the local Claude Code rally
worker, launched in `repository_path`, with the requested alias passed to
`claude --model`. This skill has
no cloud Claude peer. `claude --cloud` and `claude --environment` start an
Anthropic-hosted session against a remote snapshot, so they cannot see the local
uncommitted worktree a review targets. No cloud or remote session or subagent mode may stand in
for the local Claude peer. This restriction applies after Claude is selected;
it does not override a different peer the user explicitly named.
If the user says "Cloud <model>", ask once which they mean: local
`claude --model <model>` in `repository_path`, or an explicit remote-snapshot
session that reviews committed `HEAD` only.
