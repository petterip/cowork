# Delegation

Select the worker and model for each phase from the user’s request. Defaults
apply only where unspecified: Claude Code delegates to Codex; Codex delegates
to Claude. Other hosts use their configured peer, or ask if none is configured.
Resolve model names through the selected provider’s CLI; announce the phase,
provider, and model. Apply explicit model or family choices on launch and resume ahead of
environment defaults; otherwise preserve the route’s documented defaults,
including model-family resolution. Model choice preserves task and permissions.

Select a host-compatible route for the requested operation: `codex-build` /
`codex-review` cover Codex builds / plan reviews; the review command/router
covers code review. `codex-claude-rally` covers Codex → Claude jobs.
`cowork-gemini` and `cowork-copilot` cover their respective peers, including
Gemini via Copilot when requested. Check each planned route and dependency
before the first launch; use only supported operations and provider-specific
commands. Gemini and Copilot builds/continuations use
[the peer work launcher](peer-work.md). If the requested host/provider/
operation lacks a supported path, report that gap and ask for a choice.

Keep the user’s outcome and acceptance criteria in the orchestrator’s plan;
map each criterion to a phase or final integration check. Give the worker the
fewest task-relevant words that define success: outcome, observable acceptance
criteria, necessary inputs, essential constraints, and
output destination. Describe desired behavior rather than an ideal persona or
a list of prohibitions. Preserve safety, authorization, and scope boundaries.
Verify inputs are readable from the worker’s actual directory. Embed the
relevant frozen plan text for untracked plans or text-only workers; source
code still follows the provider’s isolation rules. Let the worker choose its
method unless the operation is fragile.

When requirements accumulate across phases, split the work instead of adding
prompt rules. The orchestrator retains the full plan; each fresh phase session
receives its task, criteria, and necessary context. Verify the result before
passing relevant findings onward. Resume within a phase for bounded fixes.
Preserve the provider’s isolation and hand-back rules: dependent edits stay in
one write job/worktree until they can safely feed the next. The orchestrator
checks the final deliverable against every original acceptance criterion,
independently runs the relevant proof, and reports unmet or unverified criteria.
A worker’s PASS or an approved phase alone does not complete the user’s task.
Changing the delegated reviewer preserves the planning steps, review-round cap,
verdict format, and human gates; use fresh requests if that peer cannot resume.
