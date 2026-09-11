---
name: codex-claude-rally
description: "Delegate bounded work from Codex to a persistent Claude Code background worker and exchange verified results through durable, versioned job artifacts. Use when the user asks to hand work between Codex and Claude, request independent Claude implementation or review, or resume a Claude worker. Launch with claude --bg; print mode is only the documented idle-fallback."
---

# Codex-Claude Rally

Use this skill for asynchronous, two-way collaboration. Codex launches Claude with `claude --bg`; Claude publishes an immutable response; Codex independently verifies it and either accepts it, asks one bounded follow-up, or escalates. Do not use `claude -p` as the primary launch. The only exception is the idle `--bg` fallback below.

Read [the job protocol](references/job-protocol.md) before creating or resuming a job.

## Subscription authentication gate

Run `scripts/assert-subscription-auth.sh` before every Claude launch and resume. It fails closed when API keys, gateway tokens, an API-key helper, Bedrock, Vertex, Foundry, or non-subscription authentication is detected. It then requires Claude Code to report an eligible first-party Claude subscription.

Anthropic account credit settings cannot be inspected from the CLI. This gate verifies subscription authentication and excludes known API/provider routes; it cannot prove whether an account has enabled optional usage credits. If the gate fails, do not change credentials automatically: report the blocker and let the user decide.

## Full-access inheritance

If the user authorized full access or Codex already has `approval_policy = "never"` and `sandbox_mode = "danger-full-access"`, every Claude and Codex child must inherit full access. `scripts/detect-full-access.sh` records this in `manifest.json`; do not silently downgrade a child to manual, read-only, or approval-gated mode.

## Preflight and recovery

Before launching a job, run `scripts/verify-environment.sh`.

- Missing worker/session: inspect `claude logs <worker-id>`; if it cannot resume, create the next immutable request and respawn.
- Unexpected permission prompt or missing full-access flag: stop the round, record `WAITING_FOR_HUMAN`, and inspect the child launch policy. Never silently downgrade access.
- Base commit, allowed-path, or proof mismatch: record `WAITING_FOR_HUMAN`; do not continue the worker speculatively.
- User cancellation: `claude stop <worker-id>`, preserve artifacts, and record `STOPPED`.

## Create a job

Resolve the target repository root before changing directories or invoking any
skill script. Pass it explicitly to job creation; `create-rally-job.sh` refuses
to infer a repository from its own process CWD. It also prints the recorded
repository and base commit to stderr for immediate verification. The external
job directory remains outside the checkout because Claude background write
sessions may move into an isolated worktree.

```bash
JOB_ID=<short-id>
TARGET_REPO=$(git rev-parse --show-toplevel)
scripts/create-rally-job.sh "$JOB_ID" read-only --repo "$TARGET_REPO" \
  --allowed-path docs --proof-command 'none'
# Use `write` only when Claude is the sole writer for the requested paths.
RALLY_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/cowork/jobs/$JOB_ID"
```

Replace the remaining placeholders in `$RALLY_DIR/requests/001.md`. Job creation
prefills mode, allowed paths, and proof command from the manifest; verify them
rather than copying them again. Add the task, source-of-truth references,
non-goals, and the absolute `$RALLY_DIR` path. Keep the request bounded; link to
long artifacts rather than copying them.

For read-only jobs, `allowed_paths` identify review targets; Claude may read the
request's declared source-of-truth files to verify findings. For write jobs,
they are the strict mutation allowlist. `rallyctl` refuses to launch an
unresolved request template.

For a write job, require every allowed path and the proof command at creation, then bind the actual isolated worker worktree before moving the job to `RUNNING`:

```bash
scripts/create-rally-job.sh "$JOB_ID" write --repo "$TARGET_REPO" \
  --allowed-path src/feature --proof-command 'pnpm test -- feature'
scripts/rallyctl.sh bind-worker "$RALLY_DIR" /absolute/worker-worktree
scripts/rallyctl.sh transition "$RALLY_DIR" CREATED RUNNING codex
```

Never let Claude and Codex edit the same paths concurrently.

The source checkout does not need to be clean. Record its branch, `HEAD`,
staged, unstaged, and untracked paths, but do not copy, stash, reset, commit, or
otherwise absorb those local changes.

A read-only `--repo` is the Git worktree root to review as it stands now,
including staged, unstaged, and untracked files, and the worker runs in that
root. Do not review `origin/main`, a remote snapshot, or any clone unless the
user asked for committed remote `HEAD`.

A write job is the isolated case: create the worker from the manifest
`base_commit` (`HEAD` at job creation), never from the source index or working
tree, and never by copying dirty source files. Local source changes are outside
the worker diff even when they touch allowed paths; resolve any hand-back
conflict only after independent verification with a non-mutating apply check.

## Launch Claude

Before writing the request, inspect the available Claude worker/model metadata.
If the worker uses Opus or Fable, keep the request especially concise: state
the outcome, source-of-truth locations, constraints, and artifact destination,
then let the model choose its investigation and solution approach. Do not
prescribe a detailed checklist unless the task is operationally fragile.

Run the gate, then pass Claude the immutable request and the absolute artifact
directory. Launch from the recorded `repository_path` so the worker sees that
working tree. Claude must write only to a temporary response file and rename it
to `responses/001.md` when complete.

```bash
scripts/assert-subscription-auth.sh
ACCESS_ARGS=()
if [[ "$(scripts/detect-full-access.sh)" == full ]]; then ACCESS_ARGS=(--dangerously-skip-permissions); fi
CLAUDE_MODEL=${CLAUDE_MODEL:-opus}   # the Claude alias the user asked for; never a peer or product name
RALLY_PROMPT="Read $RALLY_DIR/requests/001.md. Respect its mode and scope: never edit in read-only mode; in write mode modify only allowed paths. You may read declared source-of-truth files. Publish the result atomically to $RALLY_DIR/responses/001.md, append state events to $RALLY_DIR/events.ndjson, and end the response with READY_FOR_CODEX, NEEDS_CODEX, or WAITING_FOR_HUMAN."
( cd "$TARGET_REPO" && claude --bg "${ACCESS_ARGS[@]}" --model "$CLAUDE_MODEL" \
    --name "codex-$JOB_ID" --add-dir "$RALLY_DIR" --add-dir "$TARGET_REPO" \
    -- "$RALLY_PROMPT" ) 2>&1 | tee "$RALLY_DIR/claude-launch-001.txt"
claude agents --cwd "$TARGET_REPO" --all --json \
  | jq --arg name "codex-$JOB_ID" 'map(select(.kind == "background" and .name == $name))
      | max_by(.startedAt) | {id, state, cwd}'
```

Keep the `cd` inside the subshell. Every other script path in this skill is
relative to the skill directory, so leaving the shell parked in `$TARGET_REPO`
would break the later `rallyctl` and `validate-rally-job` calls.

Always separate the prompt with `--`. `--add-dir` takes a variadic
`<directories...>` list, so a prompt written straight after it is parsed as one
more directory and the session starts with no prompt at all — that is the real
cause of `idle — send a prompt to start`, not a CLI defect. The same hazard
applies to any variadic flag placed last.

`--cwd` is not a launch flag; it exists only on `claude agents`, where it merely
filters the listing. `claude -p --cwd` exits 1 with `unknown option '--cwd'`.
`claude --bg --cwd` is worse: it prints `backgrounded` and exits 0 while the
session is already `failed`, and `claude logs` then answers `job not found`. Pin
the working tree with `cd` plus `--add-dir`, never with `--cwd`.

`claude --bg` is not a flag validator. It exits 0 and prints `backgrounded` even
for an unknown option, silently taking the misparsed prompt as the session name,
and the `tee` pipeline discards the exit status anyway. The session `state` is
the only launch verdict; the launch line alone never is. Only `claude -p`
rejects a bad flag loudly, with `unknown option` and exit 1.

`claude agents --all --json` also lists interactive sessions. Those rows carry
`pid` and `status` and have no `id` and no `state`, and an interactive
`status: "idle"` has nothing to do with a background worker — select
`kind == "background"` by name and read `state`.

### Classify the launch before any fallback

| `state` of the `kind == "background"` row named `codex-$JOB_ID` | Required action |
|---|---|
| `working`, or `done` with `responses/001.md` published | `record-worker`, then wait. Inspect with `claude logs <id>` or `claude attach <id>`. Do not run print mode. |
| `blocked` — the launch line said `idle — send a prompt to start` | A variadic flag swallowed the prompt. Add the `--` separator and relaunch; do not wait on the idle session. Only if it recurs with `--` in place: read-only falls back to print mode, write moves to `WAITING_FOR_HUMAN`. |
| `failed`, or `claude logs` reports `job not found` | Read `claude logs <id>`. A `--cwd` or any other bad flag on the launch line is the known cause. Fix the flags and respawn from the same request. Never print-fallback a failed worker. |
| `stopped` | Something stopped the worker. Preserve the artifacts, record `STOPPED`, and relaunch only from a new immutable request. |
| No background row matches the name | The launch never registered a worker. Re-read the tee'd launch line and fix the flags. Never substitute a different peer, a cloud session, or a subagent. |

`claude logs` replays the worker's terminal including escape codes, so read it as
a screen capture; sparse `grep` hits there do not mean the worker is silent.

Print mode is the last resort for a read-only job whose prompt still will not
stick with `--` in place. Deliver the same request from the same directory, with
stdin closed and a streaming output format:

```bash
( cd "$TARGET_REPO" && claude -p "${ACCESS_ARGS[@]}" --model "$CLAUDE_MODEL" \
    --add-dir "$RALLY_DIR" --add-dir "$TARGET_REPO" \
    --output-format stream-json --verbose -- "$RALLY_PROMPT" \
    < /dev/null ) | tee "$RALLY_DIR/claude-print-001.txt"
```

`--output-format text` prints nothing until the whole run finishes, so it is
never a liveness signal; `stream-json` emits events from the first second. Empty
stdout is therefore not a stall: watch the tee file and the process, and stop
only on `unknown option`, a non-zero exit — print mode does report both — or
user cancellation.

Print mode yields no `--name` or worker id; skip `record-worker` on this path.
`--add-dir` does not grant writes. After the print command exits, require
`$RALLY_DIR/responses/001.md`. If it is missing, atomically publish
`claude-print-001.txt` as that response (read-only jobs only). Do not leave the
job `RUNNING` on a transcript-only run. For a write job, move to
`WAITING_FOR_HUMAN`; an idle worker is not implementing.

When `--bg` started a live worker, read the worker and session IDs from
`claude agents --cwd "$TARGET_REPO" --all --json`, then record them with the
actual worker CWD:
`scripts/rallyctl.sh record-worker "$RALLY_DIR" <worker-id>
<session-id-or-null> <worker-cwd>`. If Claude initially exposes only the worker
ID, record `null`; the same command may later fill the session ID only when the
worker ID and CWD still match. Record the Codex thread ID when one exists. If
the installed Claude version does not support a background resume, use its
documented `logs`, `attach`, `stop`, or respawn workflow; do not scrape terminal
output.

## Verify and continue

Wait for every launched or resumed worker to publish its terminal response.
Do not stop a healthy worker merely because it is slow or because a local
polling deadline elapsed. Poll status or wait in bounded intervals so Codex can
keep the user updated. Stop only on user cancellation, a confirmed stuck or
failed worker, or a protocol/safety condition that requires escalation.

When a response appears, publish it by atomic rename, then transition the manifest and run:

```bash
scripts/rallyctl.sh transition "$RALLY_DIR" RUNNING WAITING_FOR_CODEX claude
scripts/rallyctl.sh transition "$RALLY_DIR" WAITING_FOR_CODEX VERIFYING codex
scripts/validate-rally-job.sh "$RALLY_DIR"
```

Read the immutable response, inspect the full allowed-path diff against the recorded base commit, and run the proof command yourself. Write the independent finding to `reviews/001.md`; append an event and transition to `ACCEPTED`, `WAITING_FOR_HUMAN`, or `RUNNING`.

For a material fix, create `requests/002.md`; never overwrite round 001. Allow at most two transitions from `VERIFYING` back to `RUNNING`. Before any resume, re-run the subscription gate and verify the recorded base commit, worktree path, and allowed paths. Mismatch means `WAITING_FOR_HUMAN`. When `full_access_authorized` is true, resume Claude with `--dangerously-skip-permissions`. Before `ACCEPTED` or `REJECTED`, write the independent `reviews/001.md`; `rallyctl` stores its digest with the state transition.

For cancellation, use `claude stop <worker-id>`, preserve the artifacts, and transition to `STOPPED`.

## Pair with the Claude skills

`/cowork:plan`, `/cowork:review`, and `/cowork:build` cover Claude → Codex work. This skill supplies the inverse Codex → Claude entry point. Both directions use durable artifacts and independent verification rather than trusting a model's terminal report.
