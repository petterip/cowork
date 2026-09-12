# Host and peer routing

Load this reference when a public Cowork skill selects a workflow. Identify
the initiating host from the active session, never from installed binaries,
APM targets, or the skills directory. Preserve the original request, explicit
peer/model, target repository and plan/diff scope. If the host is unknown, ask
which host is initiating before launching a peer.

Default peer: Claude Code uses Codex; Codex and GitHub Copilot CLI use Claude.
The initiating host owns verification and hand-back. In a reused workflow,
references to the author describe that initiating host; the worker CLI stays
as specified. Rally's literal protocol identifiers (`WAITING_FOR_CODEX`,
`READY_FOR_CODEX`, and actor `codex`) remain unchanged even when Copilot is
the author; do not rename schema values. Do not infer a CLI from a model name.

Explicit Gemini and Copilot requests select the sibling `cowork-gemini` and
`cowork-copilot` adapters first. An explicit Codex peer selects the Codex routes
below; an explicit Claude peer selects the Rally/Claude routes. Preserve any
requested model and effort within the chosen adapter. If the adapter cannot
express them, report that limitation rather than silently dropping them.
Never call a same-model result an independent cross-model review.

All paths below are relative to the invoking public skill's real directory,
after resolving symlinks. Run tools from the task repository, not a skill
installation directory. Always pass that repository explicitly to Rally jobs.

## Claude peer

Continue with the public skill's Rally/Claude procedure. Codex and Copilot
both author the plan and independently check the worker's evidence. For
continue, use `../claude-handoff/SKILL.md`.

## Codex peer

Select exactly one route, complete it, and do not fall through to the public
skill's Claude procedure:

- **Plan:** existing plan or explicit plan review selects
  `../codex-review/SKILL.md`. Otherwise `--docs`, relevant `CONTEXT.md` or ADRs
  selects `../grill-with-docs-codex/SKILL.md`; other planning selects
  `../grill-me-codex/SKILL.md`. Preserve this precedence and original arguments.
- **Build:** use `../codex-build/SKILL.md`. Preserve its frozen-plan, isolated
  worktree, proof and hand-back contract.
- **Review:** run `../cowork-runtime/scripts/cowork-route.sh review` with the
  original scope arguments as one quoted argument. Use `adversarial-review`
  instead for custom focus or a requested challenge. The router uses the
  optional official Codex plugin or local Codex CLI fallback. Return findings
  without modifying project files. Unsupported routing flags must be surfaced.
- **Continue:** run `../cowork-runtime/scripts/cowork-route.sh transfer` with
  the requested focus as one quoted argument. Exit zero means an official
  resumable session was created. On exit 2, prepare a compact goal, state,
  decisions, artifacts, remaining-work and proof handoff, start a fresh Codex
  session in the task repository, and return the actual thread ID and exact
  resume command. Inherit full access only when already authorized. Other
  failures stop the transfer; do not claim a session exists. Do not edit
  project files during transfer.

## Status

Status does not launch a peer. Combine available official Codex status via
`../cowork-runtime/scripts/cowork-route.sh status`, Claude workers when the
CLI is available, and current plus legacy Rally manifests. Exit 2 from the
router means optional official status is unavailable. Distinguish unavailable
sources from an empty job list; report other errors. Follow the public status
skill's repository/job filters and never resume, cancel or mutate jobs.
