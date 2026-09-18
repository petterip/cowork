# 2026-09-18 Delegation validation

Validation completed for Cowork 1.4.0 on `main`, integrated on upstream
`d3804a7b13bdac69a2505f92d1282910b143c396`.
The scope was the user's outcome across delegation, not just valid Markdown
or a successful subprocess exit. No production system or application was changed.

## Findings corrected

| Failure | User impact | Correction and evidence |
|---|---|---|
| `COWORK_MODEL` overrode an explicit model argument | The wrong model performed the requested review | Explicit arguments now win; router regression reproduced the failure before the fix and passes for both Gemini and Copilot, retaining environment defaults when unspecified |
| Review examples omitted requested model arguments | User-selected reviewer was ignored on launch/resume | Build and all three Codex review workflows pass the selected model on both calls; executable snippet tests inspect received arguments |
| Detached `HEAD` lacked an untracked plan | Agent could not read the newly agreed requirements | Requests embed the relevant frozen plan text when the worker cannot read it; source-code isolation is unchanged; independent scenario replay and build check with no worker `PLAN.md` pass |
| Setup `EXIT` cleanup removed artifacts between shell calls | Later phases could not read their inputs or recover diagnostics | Build artifacts survive under the user state directory; review artifacts survive shell exits; tests exercise separate shells and retained failure evidence |
| A resume could reuse an old report/verdict | A missing response could appear successful | Each round has a new report, event log, and error log; zero-exit workers producing no report are rejected while prior artifacts remain |
| Gemini/Copilot builds and continuations had no concrete launcher | A selected peer could not carry the user’s work beyond review | Shared write launcher preserves worktree, model, access, and report contracts; mock checks cover both peers and live Gemini verifies build then continuation |
| Requested effort was not always forwarded | The selected model could run at a different effort | Codex phase launch/resume, Copilot writes, and both Gemini review input paths now receive the requested effort; argument checks pass |
| Continue command excluded model resolution from allowed tools | A named Copilot family required an extra permission step | The command allows the shared resolver; plugin contract check covers it |
| Phase success was insufficiently tied to the original request | Requirements such as offline operation could disappear between phases | Orchestrator maps every original criterion to phase or final proof and checks the complete deliverable independently |
| Changing the reviewer could bypass documentation-aware planning | The requested clarification and ADR/context steps could be skipped | Planning keeps its existing workflow; only the delegated reviewer changes, retaining round limits, verdict format, and approval boundaries |

## Acceptance evidence

| Requirement | Implementation | Verification | Status |
|---|---|---|---|
| Concise, outcome-oriented briefs | Shared delegation contract and replaced prompt templates | Independent agent replay of five user scenarios; live Claude review with a bounded request | Satisfied within tested cases |
| Phase-specific context with whole-task ownership | Original-criterion mapping, same-worktree phase sequencing, final integration proof | Independent scenario replay; two dependent mock worker phases | Satisfied within tested cases |
| Explicit models override defaults | Shared routing contract, CLI argument forwarding, peer wrapper precedence | Router tests plus build/review launch and resume argument checks | Satisfied |
| Preserve permissions and source work | Existing access detector, review sandbox flags, isolated build worker, dirty-source restrictions | Both access modes exercised for build and all three Codex review paths; rally contract checks and scenario review | Satisfied within tested boundaries |
| Reject unsupported or incomplete work honestly | Route preflight and acceptance criteria checks | Peer work launcher rejects invalid worktrees and incomplete reports; live worker rejects unverified PASS | Satisfied |
| Preserve results across calls and reject stale evidence | Per-phase/per-round artifacts | Executed Markdown shell snippets with missing output, nonzero exit, and retained previous reports | Satisfied |
| All provider operations work end to end | Provider-specific launchers | See limitations below | Partial; no universal capability claim |

## Checks run

All passed after the relevant final fixes:

```text
bash tests/test_claude_plugin.sh
bash tests/test_router.sh
bash tests/test_install.sh
bash tests/test_resolve_model.sh
bash skills/codex-claude-rally/scripts/test_contract.sh
python3 tests/test_build_workflow.py
python3 tests/test_peer_work.py
```

All 14 skills passed the skill-creator validator (using `uv run --with pyyaml`).
Shared delegation links, shell syntax, and `git diff --check` passed.
Local `codex exec resume --help` confirms the model, access, JSON, and output
options used by the examples. A separate agent reviewed the fixes and replayed
five user journeys; its final integration review found the continuation resolver allowlist gap,
which was corrected and covered by the plugin check.

The new standard-library Python check executes the skill's actual Bash examples
against a deterministic mock CLI, with a 10-second subprocess timeout. It tests
argument delivery, state continuity, failure handling and artifacts; it does not
prove a model will implement a feature correctly.

## Live delegation

The authenticated Claude subscription preflight passed. A real `claude --bg`
Opus worker reviewed two small fixture documents in an isolated local clone.
The user's requirements included online save, offline save/reopen, and old-draft
compatibility. The proposed plan omitted offline coverage and claimed PASS while
stating that verification had not run.

The worker returned **REVISE**, identified the missing offline requirement,
marked all demonstrations unverified, and requested the minimal missing proof.
The parent read the full response against both sources, verified unchanged
SHA-256 hashes and Git state, then completed the rally verification transitions.

Local evidence: `~/.local/state/cowork/jobs/validation-fcac5125d00d/` contains
`requests/001.md`, `responses/001.md`, `reviews/001.md`, the validation snapshot,
and an `ACCEPTED` manifest. Acceptance is for the review's correctness, not for
the hypothetical application. No feature implementation was run in this fixture.

## Remaining boundaries

- Gemini and Copilot now have a shared build/continuation launcher as well as
  their read-only review path. Mock checks cover both providers, explicit and
  default models, permissions, isolation, session IDs, and retained failures.
- Live Gemini build created the requested file in an isolated worker; the
  parent verified its bytes, unchanged source, and exact changed-file scope.
  Live continuation also passed after integration: exact final bytes
  `built\ncontinued\n`, only the allowed file changed, both checkout HEADs
  unchanged, source clean, exit zero, and a newly published report. The tested
  launcher snapshot was byte-compared with final source. Evidence is in
  `/tmp/cowork-peer-live-s2c4y8lc/` (`build-report.md`,
  `continue-report-002.md`, adjacent run artifacts). The initial continuation
  was excluded because editing its running launcher interrupted publication;
  the successful repeat used an immutable copy.
- The local preflight did not find a standalone `copilot` CLI; Copilot execution
  is validated with a mock, not a live authenticated provider call.
- Codex multi-phase implementation and review mechanics were executed against
  a mock worker, not a live multi-model application build. Live evidence covers
  one Claude read-only delegation plus Gemini build and continuation with
  parent-verified effects; no live Copilot execution is claimed.
- A model's future decisions cannot be guaranteed by these tests. Completion
  still requires independent evidence for the actual user's acceptance criteria.
