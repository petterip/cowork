---
name: grill-me-codex
description: "Two-act collaborative planning: Claude resolves requirements in frontier rounds, then writes PLAN.md; Codex adversarially reviews it read-only until APPROVED or MAX_ROUNDS. Require human sign-off before code. Use through /cowork:plan for high-stakes planning, documentation-aware planning, existing-plan review, or directly when requirements need structured clarification and a second-model review. Do not use for trivial changes or existing-code review."
---

# Collaborative Plan — Resolve, Challenge, Then Build

Follow [the shared delegation contract](../codex-claude-rally/references/delegation.md) from this skill’s resolved directory (follow symlinks). Named agents are defaults; explicit choices use the selected provider’s workflow.

Two acts, two different jobs:

- **Act 1 fixes the #1 failure mode: building the wrong thing.** Claude resolves intent with you until it is locked — no guessing at ambiguity. (This act is adapted from Matt Pocock's `grill-me`, used under MIT — see `THIRD-PARTY-NOTICES.md`.)
- **Act 2 fixes the #2 failure mode: a plan that sounds right but breaks.** A *different model* (Codex) adversarially attacks the locked plan. Cross-model = no echo chamber.

You enter at two points only: resolving decisions and signing off the converged plan. Codex is read-only the whole time and never touches a file.

---

## ACT 1 — COLLABORATIVE PLANNING (you ↔ Claude)

Inspect relevant code, callers, shared state, and any existing `CONTEXT.md` /
ADRs before asking. Do not interview the user for facts the repository can
answer.

Interview relentlessly until there is a shared understanding. Map the work
as a design tree. Work it in **rounds**. The **frontier** is every unresolved
decision whose prerequisites are already settled — the questions you can ask
now without guessing at answers you have not heard. Ask the whole frontier in
one round: number each question, give your recommended answer and the cost of
guessing wrong, then wait. A question that depends on another still open in this
round belongs to a later round.

"I don't know" is a valid answer. If a question is ungrillable (it needs a
prototype or other artifact to react to), stop that branch instead of guessing.
When a long list of remaining recommendations would slow the user down, offer
to accept all remaining recommendations as a batch.

When the frontier is empty and we're aligned, **write the agreed plan to
`PLAN.md`** in this structure, then move to Act 2:

```markdown
# Plan: <task>
_Locked through collaborative planning — by Claude + <user>_

## Goal
<one paragraph — reflects the decisions actually settled>

## Approach
<numbered, concrete steps>

## Key decisions & tradeoffs
<the contestable choices planning resolved — name them so the reviewer has something to challenge>

## Verification
<exact proof command(s) derived from the repo, and expected results>

## Risks / open questions
<anything still genuinely open>

## Out of scope
<bounds established during planning>
```

Initialize `PLAN-REVIEW-LOG.md`:
```markdown
# Plan Review Log: <task>
Act 1 (collaborative planning) complete — plan locked with the user. MAX_ROUNDS=<n>.
```

---

## ACT 2 — REVIEW (Claude ↔ Codex)

Now hand the locked plan to Codex for adversarial review. Same engine, mechanics verified end-to-end (2026-06-04).

### Prerequisites (verify once, fast)
- `codex --version` ≥ 0.130 (older CLIs error on the default `gpt-5.5` model).
- Codex authenticated (prior `codex login`; ChatGPT account is fine). On auth/model error, surface it — don't silently retry.
- Pin `-m` only when the user requests a model; otherwise use the config default. Pinning `gpt-5.x-codex` variants 400s on ChatGPT-account auth.
- **Echo the selected model before Round 1**: use the requested reviewer model, otherwise the configured default (or "CLI default" if unset). If the user objects, stop before launch.

### Tunables (read from args, else default)
| Var | Default | Meaning |
|-----|---------|---------|
| `MAX_ROUNDS` | `5` | Hard cap on review rounds. The loop ALWAYS terminates here. |
| `PLAN_FILE` | `PLAN.md` | The plan Act 1 produced. |
| `LOG_FILE` | `PLAN-REVIEW-LOG.md` | Append-only argument transcript. The artifact. |

If invoked with e.g. `rounds=3`, use that for `MAX_ROUNDS`. Echo resolved values before starting.

Resolve `RALLY_SCRIPTS` to `../codex-claude-rally/scripts` from this skill’s
real directory. Set `CODEX_MODEL` to the requested reviewer slug, or unset it
for the configured default.

Preserve artifact paths and thread IDs across shell calls until verification
and logging finish. Each phase approval covers only its stated criteria;
whole-plan approval requires all criteria and cross-phase contracts checked.

### The review prompt (sent each round)
Use the phase-scoped prompt below, tailored to the agreed acceptance criteria.

Before Round 1, create private per-run artifacts. Never share a predictable
`/tmp` filename between reviews:

```bash
RUN_DIR=$(mktemp -d "${TMPDIR:-/tmp}/codex-review.XXXXXX")
chmod 700 "$RUN_DIR"
PROMPT_FILE="$RUN_DIR/review-prompt.md"
VERDICT_FILE="$RUN_DIR/verdict.md"
EVENTS_FILE="$RUN_DIR/events.jsonl"
STDERR_FILE="$RUN_DIR/stderr.log"
cat >"$PROMPT_FILE" <<'EOF'
Review <current phase and relevant PLAN.md sections> against <acceptance criteria>, using repository sources as evidence. Work read-only. Report material flaws with a concrete failure scenario and concise fix; assess whether the proof catches failed implementation. Flag missing evidence. End with exactly VERDICT: APPROVED if sound enough to implement, otherwise VERDICT: REVISE.
EOF
```

### Round 1 — fresh session (capture `thread_id`)
```bash
MODEL_ARGS=()
if [[ -n "${CODEX_MODEL:-}" ]]; then MODEL_ARGS=(--model "$CODEX_MODEL"); fi
CODEX_EXEC_ACCESS=(-s read-only)
CODEX_RESUME_ACCESS=(-c 'sandbox_mode="read-only"')
if [[ "$("$RALLY_SCRIPTS/detect-full-access.sh")" == full ]]; then
  CODEX_EXEC_ACCESS=(--dangerously-bypass-approvals-and-sandbox)
  CODEX_RESUME_ACCESS=(--dangerously-bypass-approvals-and-sandbox)
fi
if ! timeout 600 codex exec "${CODEX_EXEC_ACCESS[@]}" "${MODEL_ARGS[@]}" --json -o "$VERDICT_FILE" "$(<"$PROMPT_FILE")" \
  < /dev/null >"$EVENTS_FILE" 2>"$STDERR_FILE"; then
  printf 'Codex review failed; inspect %s and %s.\n' "$EVENTS_FILE" "$STDERR_FILE" >&2
  exit 1
fi
THREAD_ID=$(jq -r 'select(.type == "thread.started") | .thread_id' "$EVENTS_FILE" | head -n1)
[[ -n "$THREAD_ID" && "$THREAD_ID" != null && -s "$VERDICT_FILE" ]] || { printf 'Codex did not return a thread ID and verdict.\n' >&2; exit 1; }
```
The critique is in `$VERDICT_FILE`. Confirm both a thread ID and nonempty verdict; on failure report the private diagnostics. **`< /dev/null` is mandatory:** `codex exec` reads stdin in addition to the prompt arg, so under a non-interactive driver it blocks forever waiting on stdin EOF.

### Rounds 2..MAX — resume the SAME session (Codex remembers its prior critiques)
```bash
# resume REJECTS -s. Force read-only via -c sandbox_mode, or Codex inherits
# config.toml (possibly danger-full-access) and could WRITE files. This is the
# single most important safety line in the skill — verified 2026-06-04.
VERDICT_FILE=$(mktemp "$RUN_DIR/verdict.XXXXXX")
EVENTS_FILE="$VERDICT_FILE.events.jsonl"
STDERR_FILE="$VERDICT_FILE.stderr.log"
if ! timeout 600 codex exec resume "$THREAD_ID" "${CODEX_RESUME_ACCESS[@]}" "${MODEL_ARGS[@]}" --json \
  -o "$VERDICT_FILE" \
  "I revised the plan. Re-review the same phase of PLAN.md against its acceptance criteria; check prior findings and new material flaws. End with VERDICT: APPROVED or VERDICT: REVISE." \
  < /dev/null >"$EVENTS_FILE" 2>"$STDERR_FILE"; then
  printf 'Codex review resume failed; inspect %s and %s.\n' "$EVENTS_FILE" "$STDERR_FILE" >&2
  exit 1
fi
[[ -s "$VERDICT_FILE" ]] || { printf 'Codex resume returned no verdict.\n' >&2; exit 1; }
```
Both `codex exec` and `codex exec resume` support `--json` and `-o/--output-last-message`. The `< /dev/null` redirect is required on the resume call too — same non-interactive stdin hang as Round 1.

**Timeout guard (both rounds):** run every `codex exec` / `codex exec resume` with a 10-minute ceiling so any future stall fails loud instead of hanging silently. Via Claude Code's Bash tool, pass `timeout: 600000` on the tool call (the default 2-minute tool timeout is too short for real reviews and would kill them mid-run). In a plain shell, prefix the command with `timeout 600` (Linux / Git Bash) or `gtimeout 600` (macOS via coreutils — stock macOS has no `timeout`). If the ceiling trips, treat it as a failed run: stop and tell the user rather than retrying blind.

### Each round, after Codex returns
1. Confirm the resume exits successfully and `$VERDICT_FILE` is nonempty; otherwise stop. Read `$VERDICT_FILE`; append to `LOG_FILE`: `## Round <n> — Codex` + the full critique.
2. Grep the last line for the verdict:
   - `VERDICT: APPROVED` → break to Resolution (converged).
   - `VERDICT: REVISE` → Claude decides **what's actually worth acting on** (Claude is final arbiter — Codex advises, doesn't command). Revise `PLAN_FILE`. Append `### Claude's response` to `LOG_FILE`: what changed, what was rejected, why. Increment round.
3. If round > `MAX_ROUNDS` → break to Resolution (deadlock).

### Resolution (you sign off — final gate)
- **APPROVED:** present the final `PLAN_FILE`, a 3-bullet summary of what the two acts improved, and the round count. Ask: *"Plan refined and challenged through N Codex rounds. Implement it now — Codex builds it (`/cowork:build`), Claude builds it, or stop here?"* Code only on a yes. **No code is written during either act.**
- **MAX_ROUNDS hit without APPROVED (deadlock):** do NOT fake convergence. List each unresolved point + Claude's counter-position; hand it to the user to break the tie. A flagged disagreement beats a false "approved."

### ACT 3 (optional) — BUILD (Codex ↔ Claude, roles flipped)

If the user picks Codex: invoke the `codex-build` skill with `SPEC_FILE=PLAN.md` and the same `LOG_FILE` — it appends `## Act 3 — Build` to the log, so one artifact tells the whole story (grilled → reviewed → built → verified). Roles flip: Codex writes the code with full access, Claude reviews the diff and runs the proof. If the user picks Claude, implement directly as usual.

---

## Hard rules
- Act 1 always precedes Act 2 — don't write `PLAN.md` until collaborative planning has resolved the decision tree with the user.
- Full access is inherited when authorized or already configured; otherwise Codex is read-only every round. The reviewer prompt forbids edits in both cases.
- The loop ALWAYS terminates at `MAX_ROUNDS`.
- Claude is final arbiter on every REVISE — incorporate good critiques, reject bad ones *with a logged reason*. Don't cave to everything (defeats the cross-model check) and don't ignore it (defeats the point).
- Code only after the user's final sign-off.
- `LOG_FILE` is the deliverable — keep the complete decision record.

## What NOT to do
- Don't review already-written code — that's `/codex:review`.
- Don't pin a `-codex` model variant on ChatGPT-account auth — it 400s.
- Don't let Codex edit files. Read-only, always.
- Don't skip Act 1 — collaborative planning is half the value.
