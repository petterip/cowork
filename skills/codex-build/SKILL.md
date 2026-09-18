---
name: codex-build
description: "Cross-model implementation from a frozen spec: Codex builds in an isolated worktree, then Claude reviews the complete diff, runs proof, and sends bounded fixes to the same Codex session. Preserve dirty source checkouts and require human approval before applying or committing. Use through /cowork:build for well-specified refactors, migrations, reproducible bugs, and tests. Do not use for tiny edits, design work, existing-code review, or work requiring Claude-session-only tools."
---

# Codex-Build — Codex Types, Claude Verifies

Follow [the shared delegation contract](../codex-claude-rally/references/delegation.md) from this skill’s resolved directory (follow symlinks). Named agents are defaults; explicit choices use the selected provider’s workflow.

The role-flip of `/cowork:plan` plan review: there, Claude builds the plan and Codex critiques read-only. Here, **Codex is the builder with write access; Claude is the spec-writer and reviewer.** Codex implements a frozen spec end-to-end; Claude judges the diff like a contributor PR, demands proof, and iterates fixes in the same Codex session. The human enters at exactly two points: kickoff and diff sign-off.

Adapted from Peter Steinberger's `codex-first` pattern (agent-scripts), rebuilt on this house's verified Codex mechanics.

**Spec quality decides success.** Derive each phase’s outcome and acceptance criteria from the frozen plan. Fresh phase sessions share the isolated worker worktree; verify each phase and the combined diff and proof before hand-back. Same-session resumes fix the current phase.

## Prerequisites (verify once, fast)

- Resolve `COWORK_PLUGIN_ROOT` to the plugin root two directories above this
  skill before invoking its scripts.
- `codex --version` ≥ 0.130 (older CLIs error on the default `gpt-5.5` model).
- Codex authenticated (prior `codex login`; ChatGPT account is fine). On auth/model error, surface it — don't silently retry.
- Do NOT pin `-m` or model config (e.g. `model_reasoning_effort`) unless the user asks. Pinning `gpt-5.x-codex` variants 400s on ChatGPT-account auth; config defaults come from `~/.codex/config.toml`.
- When the user names a Codex model or reasoning effort, pin whichever was
  named — each is resolved independently, so a model without an effort (or
  vice versa) is normal — for every fresh build invocation. Resolve a family
  name from Codex's live catalog with
  `$COWORK_PLUGIN_ROOT/scripts/resolve-model.sh --family named --via codex
  --query "<requested family>"`; use a full slug directly only when the user
  supplied it. Pass a requested effort unchanged as
  `-c model_reasoning_effort=<level>` and let Codex validate support. These are
  `codex exec` options, not text for the build prompt. Do not probe for a
  model-named binary, invent a version, or silently fall back to the configured
  model if the requested model is unavailable.
- **Echo the active model at kickoff** so the user can confirm: read the `model` line from `~/.codex/config.toml` (absent = "CLI default"); state it with the resolved tunables. If the user objects, stop before launching the build.
- **Codex has a native image-generation tool** in `codex exec` sessions (ChatGPT-account backed, no API key; verified 2026-07-08 — it saved a generated PNG to disk headless). Specs may therefore include "generate these image assets yourself" steps: name exact file paths, dimensions, and style in the prompt contract.
- Resolve the target repo root first. Codex runs from the isolated worker root
  created in Step 0 (`resume` does not support `-C`).

## Tunables (read from args, else default)

| Var | Default | Meaning |
|-----|---------|---------|
| `SPEC_FILE` | `PLAN.md` | The frozen spec Codex implements. |
| `MAX_FIX_ROUNDS` | `2` | Fix iterations via resume before Claude takes over and finishes directly. |
| `LOG_FILE` | `PLAN-REVIEW-LOG.md` | Append-only build transcript. If it exists (Act 1/2 ran), append `## Act 3 — Build`; else create it. |
| `PROOF_CMD` | phase verification | Exact proof command and expected result for this phase, derived from the spec. Keep the full spec’s verification for final integration. Resolve missing proof before launch. |

Echo resolved values before starting.

For a multi-phase build, run Step 0 once. Repeat Steps 1–4 sequentially for each
phase in that worktree, resolving its selected provider/model and capturing a
fresh thread ID and report in the log. Use that provider’s supported launcher;
these CLI examples are Codex-only. Same-phase fixes resume that phase’s thread.
Proceed to Step 5 after all phases and combined verification pass.

## Step 0 — Gates (before any Codex launch)

1. **Spec gate.** `SPEC_FILE` must exist and read as a work order (goal, concrete steps, bounds). No spec → offer `/cowork:plan`, which can clarify or review an existing plan. If the user insists on building from a rough idea, write the spec WITH them first — that's design, and design stays with Claude.
2. **Source-state snapshot.** Record the source root, branch, `HEAD`, staged,
   unstaged, and untracked paths. A dirty source is allowed. Do not stash,
   reset, commit, copy, clean, or otherwise absorb its local changes.
3. **Isolated worker.** Create a detached Git worktree from the recorded `HEAD`
   in a dedicated temporary directory. Run every Codex build/resume, diff, and
   proof command there. The source index and working tree never enter the
   worker, so pre-existing local work is ignored by construction.
4. Confirm scope in one line, then go. No round-by-round approvals; the human gate is at the end.

Resolve `RALLY_SCRIPTS` to `../codex-claude-rally/scripts` from this skill’s
real directory. Initialize once; the existing access detector honors explicit
`COWORK_FULL_ACCESS_AUTHORIZED=1` or configured full access:

```bash
BUILD_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/cowork/builds"
mkdir -p "$BUILD_ROOT"
BUILD_DIR=$(mktemp -d "$BUILD_ROOT/run.XXXXXX")
chmod 700 "$BUILD_DIR"
BUILD_ACCESS=()
if [[ "$("$RALLY_SCRIPTS/detect-full-access.sh")" == full ]]; then
  BUILD_ACCESS=(--dangerously-bypass-approvals-and-sandbox)
fi
```

Keep the artifact paths and session IDs across shell calls; retain this directory
for verification and recovery. Record its path in `LOG_FILE`.

## Step 1 — The build prompt (contract, via temp file)

Write this contract from the frozen phase into the prompt file. Embed its
acceptance criteria and needed decisions when the plan is untracked or absent
from the worker; do not copy dirty source code. Confirm referenced inputs are
readable from the isolated worker before launch. Set `CODEX_MODEL` and `CODEX_EFFORT` only from this phase's explicit request,
resolving each independently. Resolve family names through the live catalog,
including models published after this skill. Unset unspecified values to keep
configured defaults; preserve the array for same-phase fixes:

```bash
CODEX_ARGS=()
if [[ -n "${CODEX_MODEL:-}" ]]; then
  CODEX_ARGS+=(-m "$CODEX_MODEL")
fi
if [[ -n "${CODEX_EFFORT:-}" ]]; then
  [[ "$CODEX_EFFORT" =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]] || { printf 'Invalid effort token.\n' >&2; exit 1; }
  CODEX_ARGS+=(-c "model_reasoning_effort=$CODEX_EFFORT")
fi
PHASE_DIR=$(mktemp -d "$BUILD_DIR/phase.XXXXXX")
P="$PHASE_DIR/prompt.md"
cat >"$P" <<'EOF'
GOAL: <current phase’s outcome and observable acceptance criteria>
SPEC: <frozen phase text, or exact sections of a worker-readable spec>; implement this phase.
  Report blocked requirements or necessary deviations with reasons.
KEY PATHS: <allowed edit paths and relevant readable sources>
CONSTRAINTS: <essential compatibility, safety, and authorization boundaries>
PROOF: Run `<PROOF_CMD>`; expected result: <what demonstrates acceptance>.
OUTPUT: Report changed paths and why, full proof output, and deviations.
EOF
```

## Step 2 — Launch Codex (fresh session, capture `thread_id`)

```bash
BUILD_REPORT="$PHASE_DIR/report.md"
BUILD_EVENTS="$PHASE_DIR/events.jsonl"
BUILD_STDERR="$PHASE_DIR/stderr.log"
if ! timeout 600 codex exec "${BUILD_ACCESS[@]}" "${CODEX_ARGS[@]}" --json -o "$BUILD_REPORT" - <"$P" >"$BUILD_EVENTS" 2>"$BUILD_STDERR"; then
  printf 'Codex build failed; inspect %s and %s.\n' "$BUILD_EVENTS" "$BUILD_STDERR" >&2
  exit 1
fi
THREAD_ID=$(jq -r 'select(.type == "thread.started") | .thread_id' "$BUILD_EVENTS" | head -n1)
[[ -n "$THREAD_ID" && "$THREAD_ID" != null && -s "$BUILD_REPORT" ]] || { printf 'Codex did not return a thread ID and report.\n' >&2; exit 1; }
```

- Prompt goes via stdin (`- <"$P"`) — this both avoids quoting bugs AND sidesteps the non-TTY stdin hang (`codex exec` blocks forever waiting on stdin EOF under Claude Code's Bash tool; feeding the file gives immediate EOF).
- Parse `thread_id` from `$BUILD_EVENTS` → `THREAD_ID`. Codex's final report lands in `$BUILD_REPORT` — read that file; do not parse the JSONL stream for content.
- Confirm success by the report file + a `thread.started` line; neither means a failed run (auth/model) — stop and tell the user. Keep private diagnostics in `$BUILD_STDERR`.
- **Timing:** foreground with `timeout: 600000` on the Bash tool call (default 2-min tool timeout kills real builds). If the spec is clearly >10 min of work (multi-file feature, migration, anything with image generation), launch with `run_in_background: true` instead and read the `-o` file when it exits. Don't kill a quiet background run early — Codex builds are legitimately slow.
- **Heads-up on completion (required):** when a background Codex run finishes, the FIRST line of your next message to the user must be a loud standalone banner — `🔔 CODEX FINISHED — <what> (exit ok/fail) — verifying now` — BEFORE any verification output. The user is not watching tool calls; never let a completed build slide silently into the verify phase.

## Step 3 — Verify (Claude, always, never delegated)

Codex's report is advisory. Verify in the isolated worker:

1. `git status -sb` + read the FULL diff (`git diff`). Judge it like a contributor PR: correctness, spec fidelity, style match with surrounding code, nothing touched outside scope.
2. Run `PROOF_CMD` yourself (or the focused tests for the changed area). Codex's pasted output doesn't count as proof.
3. Check newly created/untracked files as well as tracked changes, and map proof
   results to the phase’s acceptance criteria. At final verification cover the
   original user request and full integration proof, including cross-phase behavior.
4. Append to `LOG_FILE` under `## Act 3 — Build`: `### Round <n> — Codex build` + its report summary + `### Claude's verdict` + what passed/failed review.

## Step 4 — Fix loop (same session, bounded)

Problems found → resume the SAME session (Codex keeps its context; cheaper and better than a fresh run). Write the fix list to a temp file (`$P2`), same contract discipline: exact problem, exact file, proof expected.

```bash
# Resume from the worker directory with the same authorized access and model.
BUILD_REPORT=$(mktemp "$PHASE_DIR/fix-report.XXXXXX")
BUILD_EVENTS="$BUILD_REPORT.events.jsonl"
BUILD_STDERR="$BUILD_REPORT.stderr.log"
if ! timeout 600 codex exec resume "$THREAD_ID" "${BUILD_ACCESS[@]}" "${CODEX_ARGS[@]}" --json \
  -o "$BUILD_REPORT" - <"$P2" >"$BUILD_EVENTS" 2>"$BUILD_STDERR"
then
  printf 'Codex build resume failed; inspect %s and %s.\n' "$BUILD_EVENTS" "$BUILD_STDERR" >&2
  exit 1
fi
[[ -s "$BUILD_REPORT" ]] || { printf 'Codex resume returned no report.\n' >&2; exit 1; }
```

Re-verify (Step 3) after each round. After `MAX_FIX_ROUNDS` failed rounds: STOP delegating — Claude takes over and finishes the remaining fixes directly. Log the takeover. Ping-ponging trivia through delegation burns more than it saves.

## Step 5 — Human gate (diff sign-off)

Present: 3-bullet summary of what was built, files-changed list, proof-test output (pass/fail, verbatim tail), rounds used, any spec deviations. Before hand-back, run a non-mutating apply check against the current source checkout. If local work overlaps, report the conflict and ask how to resolve it; never overwrite it. Otherwise ask: *"Codex built it, proof passes, and the diff applies cleanly beside your local changes. Apply and commit?"*

- Apply or commit ONLY on yes — and Claude performs the hand-back, never Codex.
- Rejected → ask what's wrong, route back to Step 4 (or take over directly if fix rounds are spent).

Claude's Step 3 inspection of the complete Codex-authored diff and independent
proof run is the cross-model review built into this workflow. A request to
"build, then have cowork independently review" is satisfied by that required
review; do not launch a redundant second job. If the user explicitly asks for
an additional reviewer or another review model, run `/cowork:review` (or
`cowork-review`) in a **fresh** read-only session. Do not reuse the builder
session, and do not treat a review as covering edits made afterward.

## Hard rules

- Dirty source trees are allowed and must remain untouched. All writes happen
  in the isolated worker created from the recorded source `HEAD`.
- Claude never skips the diff read. Codex claims are advisory until Claude has read the diff and run the proof.
- Fix loop terminates at `MAX_FIX_ROUNDS` — then Claude takes over. No unbounded delegation ping-pong.
- Commits, pushes, releases, GitHub mutations: Claude-side only, after the human gate. Codex never commits.
- `LOG_FILE` is the deliverable — with Acts 1/2 it tells the whole story: planned → reviewed → built → verified.

## What NOT to do

- Don't build without a spec — that's designing by delegation, and it fails. Route to `/cowork:plan` first.
- Don't use for ~<20-line single-obvious-change edits — just make the edit.
- Don't pin `-codex` model variants on ChatGPT-account auth — 400s.
- Don't resume with `--last` — capture and use the explicit `THREAD_ID` (parallel sessions make `--last` grab the wrong thread). And ECHO the id into the command visibly before running: `resume` with a missing/garbage id can silently fall back to the most recent session instead of erroring (observed 2026-07-08) — a wrong-target resume looks exactly like a successful one.
- Don't parse the JSONL stream for the report — read the `-o` file.
- Don't let Codex commit, and don't auto-commit yourself — human gate first.
