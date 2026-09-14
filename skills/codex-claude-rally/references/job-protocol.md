# Rally job protocol

Use one external directory per job:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/cowork/jobs/<job-id>/
├── manifest.json
├── state.md
├── events.ndjson
├── requests/001.md
├── responses/001.md
└── reviews/001.md
```

Never use an in-checkout mailbox for a write job. Claude Code can isolate a background writer in a worktree, which would make the checkout's mailbox a different copy.

## Manifest

`manifest.json` is the source of truth. It contains:

- `schema_version`: `1`
- `job_id`, `mode`, `repository_path`, and `base_commit`
- `state`, `owner`, and `round`
- `claude_worker_id`, `claude_session_id`, `worker_cwd`, and `codex_thread_id` when known
- `full_access_authorized`, inherited by every Claude and Codex child session
- `allowed_paths`, `proof_command`, and `created_at`
- immutable request, response, and review SHA-256 digests by round

`repository_path` is always an explicitly supplied, canonical Git worktree
root, and every Claude launch runs with it as the process CWD. Job creation must
not derive it from the skill script's current working directory. For a read-only
job it is the tree to review as it stands, including staged, unstaged, and
untracked files. For read-only jobs, `allowed_paths` are review targets and the
request may declare additional readable source-of-truth files. For write jobs,
`allowed_paths` are the strict mutation allowlist.

Only the owner of the current state changes the manifest through `scripts/rallyctl.sh`; it locks the job and atomically updates `manifest.json`, `state.md`, and `events.ndjson`. Keep `state.md` as a concise human-readable projection.

## States

```text
CREATED → RUNNING → WAITING_FOR_CODEX → VERIFYING → ACCEPTED
                                      └→ RUNNING
                                      └→ WAITING_FOR_HUMAN
                                             └→ RUNNING
                                             └→ STOPPED | REJECTED
Other active states → STOPPED
```

- `CREATED`: request is complete; no worker has started.
- `RUNNING`: Claude owns the requested work.
- `WAITING_FOR_CODEX`: Claude published a response and needs review or a decision.
- `VERIFYING`: Codex owns independent diff and proof verification.
- `WAITING_FOR_HUMAN`: an immutable scope, base, path, or product decision is missing.
- `ACCEPTED`, `REJECTED`, `STOPPED`: terminal states.

Count a follow-up when `VERIFYING` or `WAITING_FOR_HUMAN` returns to
`RUNNING`. Cap it at two and require a new immutable request for the next
round.
`CREATED -> RUNNING` and every follow-up launch validate that all request
sections contain real content and no template placeholders remain.

## Artifact rules

- Publish a finished artifact atomically: write `*.tmp`, then rename it.
- Never overwrite a completed request, response, or review; increment the three-digit round.
- `rallyctl` records the request digest when launching, the response digest when entering `WAITING_FOR_CODEX`, and the independent review digest when accepting or rejecting. It rejects a changed artifact before the next ownership transition.
- `events.ndjson` is append-only and contains only timestamp, actor, state, artifact path, and exit status.
- Link to durable source artifacts instead of copying large source text.
- Worker metadata is immutable except that a `null` Claude session ID may be
  filled later when the recorded worker ID and CWD match exactly. Re-recording
  identical metadata is idempotent; conflicting metadata fails closed.

## Write-job hand-back

Claude may write only to its recorded, isolated worker worktree. The job creator must declare at least one normalized relative allowed path for a write job. Codex verifies the worker diff and untracked files against that allowlist and `base_commit`, then explicitly asks the user before merging, cherry-picking, or applying it. Read-only jobs may use a shared checkout only when no other writer is active.

The source checkout may have staged, unstaged, and untracked changes. Record
that state for attribution, then ignore it when creating the worker: the worker
starts from `base_commit`, never from the source index or working tree. Do not
stash, reset, commit, copy, or clean the source changes. Before hand-back, run a
non-mutating apply check against the current source checkout. A conflict or an
overlap is a hand-back decision for the user; it is not permission to overwrite
their local work.

When `full_access_authorized` is true, pass each provider's full-access flag to its child session. A review may still instruct the model not to edit, but that instruction must not be implemented by downgrading the child sandbox or permission mode.

## Recovery table

| Condition | Required action |
|---|---|
| Worker or session missing | Inspect its documented log/status; respawn only from a new immutable request. |
| `--bg` prints `backgrounded` but the session state is `failed` | Read `claude logs <id>`. A `--cwd` on the launch line is the known cause; `--cwd` is valid only on `claude agents`. Fix the flags and respawn. Never print-fallback a failed worker. |
| `--bg` reports `idle — send a prompt to start` (state `blocked`) | A variadic flag such as `--add-dir` swallowed the prompt: separate it with `--`, rerun the peer-egress gate, and relaunch. Only if it recurs with `--` in place, read-only: rerun the gate and deliver the same request with `claude -p` (never `--cwd`), `--add-dir` of the job directory and the repository, `--output-format stream-json`, and stdin closed. Empty stdout is not a stall. If `responses/001.md` is still missing once it exits, the parent publishes the captured stdout. Write: `WAITING_FOR_HUMAN`. |
| The named peer has no local CLI launch | Move to `WAITING_FOR_HUMAN`. Never substitute a cloud session, a clone, or another vendor's agent for the named peer. |
| Permission prompt appears unexpectedly | Stop the round and move to `WAITING_FOR_HUMAN`; inspect access inheritance. |
| Base commit, allowed paths, or proof differs | Move to `WAITING_FOR_HUMAN`; do not continue speculatively. |
| User cancels | Stop the worker, preserve artifacts, and move to `STOPPED`. |
