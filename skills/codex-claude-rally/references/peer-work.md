# Gemini and Copilot build / continuation

Use `scripts/invoke-peer-work.sh` from the plugin root for write work. Resolve
that root from the invoking skill's real directory. Reviews continue to use
`invoke-peer-review.sh`; its read-only constraints are not builder permissions.

For a build, follow `codex-build` planning, source snapshot, isolated worktree,
proof, and hand-back steps, replacing only the worker launch. Create the worker
from the recorded source `HEAD`. Subsequent phases use that same worker after
independent verification and the preceding writer's completion, so they retain
verified edits without importing the user's dirty source files. A completed
Claude rally phase may hand its recorded worker worktree to this launcher.
Keep allowed paths, acceptance criteria, relevant frozen plan text, and proof
in the phase request; the parent verifies the full diff, including new files.

For continuation, pass a compact handoff with the next outcome, criteria,
relevant state, sources, and remaining proof. Use the existing worker when
continuing a build. Otherwise use the user's current repository, including its
local work, with the receiving agent as sole writer within the existing user
authorization. Record its dirty state first and preserve unrelated changes.
This starts a fresh receiving session by default, not a verified build or merge.

Create each request/report outside both checkouts, for example under
`${XDG_STATE_HOME:-$HOME/.local/state}/cowork/`. Use an absolute, unused report
path for every launch and correction; failed-run diagnostics remain beside it.

```bash
# Replace agy with copilot for GitHub Copilot. Use auto or the requested slug.
"$COWORK_PLUGIN_ROOT/scripts/invoke-peer-work.sh" build agy auto \
  --source-repo "$SOURCE_REPO" --repo "$WORKER_REPO" \
  --prompt-file "$PHASE_REQUEST" --output "$PHASE_REPORT"

"$COWORK_PLUGIN_ROOT/scripts/invoke-peer-work.sh" continue copilot auto \
  --repo "$WORKER_REPO" --prompt-file "$HANDOFF_REQUEST" --output "$HANDOFF_REPORT"
```

For Gemini through Copilot, use `copilot auto --family gemini-flash`. An exact
model argument wins over `COWORK_MODEL`; an explicit Gemini family resolves
that family instead of an ambient model. For any other requested Copilot family,
resolve it with `scripts/resolve-model.sh --family named --via copilot --query
"<requested family>"` and pass the returned slug. Forward a requested effort
with `--effort <level>`; the selected peer validates support. Otherwise keep the
configured default.
Full access is inherited through `detect-full-access.sh`; without it the peer
retains its normal permission controls. Report denied operations and unmet
criteria rather than enabling bypass permissions to get a passing result.

When resuming a known session, add `--session "$SESSION_ID"` only after checking
its recorded provider, model and working directory match this phase. The
launcher uses `agy --conversation` or `copilot --resume=ID`; it never selects
the latest conversation. If no verified ID is available, use a fresh handoff.
Record provider session IDs when returned; do not invent or infer them from a
successful process exit. A new phase/provider starts fresh even if the prior
phase has a resumable ID.

The parent waits for completion and independently checks the result and proof
against the original criteria. A nonempty report is transport success only.
Retry a failed run with a new report path after inspecting its diagnostics;
keep the existing bounded fix-round limit. User cancellation stops the receiving
process, preserves its artifacts, and leaves the work unaccepted. Existing
source hand-back and publication authorization boundaries still apply.

Provider arguments: the installed `agy --help` documents `--mode accept-edits`,
`--conversation`, and `--print-timeout`; GitHub documents the corresponding
[Copilot programmatic and session options](https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference).
