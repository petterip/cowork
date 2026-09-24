# Cowork

Use one model to plan, build, review, or continue work with another. Cowork
selects the direction from the environment and keeps material work bounded and
verifiable. Claude, Codex, Anti-Gravity, and GitHub Copilot are peers.

## Commands

| Goal                        | Claude Code        | Codex             |
| --------------------------- | ------------------ | ----------------- |
| Plan before coding          | `/cowork:plan`     | `cowork-plan`     |
| Build an approved plan      | `/cowork:build`    | `cowork-build`    |
| Review current work         | `/cowork:review`   | `cowork-review`   |
| Continue in the other model | `/cowork:continue` | `cowork-continue` |
| Show jobs                   | `/cowork:status`   | `cowork-status`   |
| Check setup                 | `/cowork:setup`    | `cowork-setup`    |

In Claude Code, Codex is the default other model. In Codex, Claude is the
default other model. The `cowork` skill is the front door on hosts that have no
`/cowork:*` commands: it routes a one-shot peer question to
`scripts/invoke-peer-review.sh` and escalates to a durable job only when the
work must be built, resumed, or audited. The defaults are only defaults: the
user can choose a supported
provider and model separately for each phase where that operation is supported.
All routes follow the [delegation contract](skills/codex-claude-rally/references/delegation.md).
Model names are opaque user data, not peer names. When a request names both a
peer and a model, the peer wins. Otherwise Cowork matches the name against the
catalogs discovered on that workstation and proceeds only when one peer/id is
unambiguous. With a selected peer, catalogs are alias hints, never allowlists:
unmatched or ambiguous model names pass unchanged to that CLI. Numeric versions
are matched as whole values; a requested version is never reduced to an older one. No model names or versions are built into routing logic.

Select a peer explicitly with `--peer`; legacy peer-specific flags remain
accepted for compatibility.
Pass `--model <name-or-id>` only when the user requested one; otherwise the
selected peer uses its native default. Anti-Gravity and Copilot
use separate review and [write/continuation launchers](skills/codex-claude-rally/references/peer-work.md).
Build phases share an isolated worktree; continuation uses a compact fresh
handoff or an explicitly identified session.

`plan` also covers documentation-aware planning and review of an existing
plan. `build` requires an approved plan and independent proof. `review` never
edits. `continue` transfers the current context without pretending it is a
verified build.

## Usage examples

From Codex or GitHub Copilot CLI, ask the `cowork-review` skill to review local
changes with a user-selected peer and model:

```text
cowork-review Review the changes using Copilot with model <name>. Focus on boundary regressions.
```

Cowork resolves the supplied name from Copilot's discovered catalog, reviews
the working tree read-only, and leaves the initiating model to verify and apply
any findings.

From Claude Code, build a frozen plan with an explicitly selected Codex model:

```text
/cowork:build PLAN.md with Codex model <name> at low reasoning effort, then have cowork independently review the result.
```

Cowork resolves the requested name from Codex's discovered catalog and runs the
isolated builder with the requested effort. The initiating peer then inspects
the complete diff and runs the plan's proof command independently.

Discover the workstation once before the first delegation or after upgrading a
peer CLI:

```bash
scripts/cowork setup --refresh
scripts/cowork doctor
```

The capability manifest lives under `${XDG_STATE_HOME:-$HOME/.local/state}` and
is automatically refreshed when Cowork or a peer CLI version changes.

Peer launches use the selected CLI and its existing authentication. Follow the
consumer repository's rules for shared context and keep prompts limited to the
task. Never include PHI, PII, credentials, customer data, or other regulated
material in peer prompts.

## Install

APM (one dependency containing all Cowork skills):

```bash
apm install petterip/cowork --target agent-skills,claude,codex,copilot
```

In another APM package, declare `petterip/cowork` once instead of declaring
each `petterip/cowork/skills/*` path. APM locks the repository revision and
lists one `cowork` package while projecting `cowork-setup`, `cowork-plan`, and
the other skills to the selected runtimes. The skills locate their shared
runtime from the installed package under `apm_modules`.

Claude Code:

```text
/plugin marketplace add petterip/cowork
/plugin install cowork@cowork
/reload-plugins
```

GitHub Copilot CLI plugin:

```text
/plugin marketplace add petterip/cowork
/plugin install cowork@cowork
/skills reload
```

Update an existing Copilot installation with `/plugin marketplace update cowork`,
`/plugin update cowork`, then `/skills reload`.

Codex:

```bash
./install.sh --agent codex
```

opencode:

```bash
./install.sh --agent opencode
```

DeepSeek Harness and other hosts that discover `~/.agents`:

```bash
./install.sh --agent dsh
```

The skills are linked into `$DSH_AGENTS_HOME/skills`, which defaults to
`~/.agents/skills` and is the user skill root those hosts read.

GitHub Copilot CLI skills from a clone:

```bash
./install.sh --agent copilot
```

Install Claude Code and Codex from a clone:

```bash
./install.sh --agent both
```

Install everywhere (Claude Code, Codex, opencode, Copilot, and `~/.agents` hosts):

```bash
./install.sh --agent all
```

Audit or repair an existing installation without guessing:

```bash
./install.sh --check --agent all   # report missing, stale, and foreign links
./install.sh --repair --agent all  # replace dangling links to a renamed clone
```

`--check` writes nothing and exits non-zero while any link needs attention.
`--repair` replaces only dangling links that point at a Cowork checkout, which
is what a renamed clone leaves behind; a link or directory this installer does
not own stays a collision and is never moved.

The official `codex@openai-codex` Claude Code plugin is optional. When present,
Cowork uses its review, adversarial-review, status, and session-transfer paths.
Without it, normal reviews use the local Codex CLI; `continue` creates a fresh
Codex handoff, and official-plugin-only features report that requirement.

The GitHub Copilot peer is the standalone `copilot` binary, not the older
`gh copilot` suggestion extension.

## How material work is handled

- Read-only work runs as a bounded second-model review.
- Write jobs use an isolated worktree created from the recorded source `HEAD`
  and explicit allowed paths. The source checkout may be dirty; staged,
  unstaged, and untracked user work stays local and is not copied into the
  worker. Hand-back must apply-check rather than overwrite local work.
- Requests, responses, reviews, and state transitions are durable artifacts.
- The initiating model verifies the diff and proof before acceptance.
- Commits, pushes, deployments, and credential changes remain human-gated.

New artifacts live outside the checkout:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/cowork/jobs/<job-id>/
```

Status still reads legacy manifests from
`${XDG_STATE_HOME:-$HOME/.local/state}/cowork-claude-codex/jobs`.

## Verify the package

```bash
tests/test_claude_plugin.sh
tests/test_router.sh
tests/test_install.sh
tests/test_resolve_model.sh
python3 tests/test_cowork_cli.py
python3 tests/test_build_workflow.py
python3 tests/test_peer_work.py
python3 tests/test_peer_review.py
python3 tests/test_doctor.py
skills/codex-claude-rally/scripts/test_contract.sh
```

Check the authenticated local environment separately before a real job:

```bash
skills/codex-claude-rally/scripts/verify-environment.sh
```

The Claude subscription check blocks known API/provider authentication and
requires a first-party subscription login. Claude Code cannot expose whether
optional account-level usage credits are enabled. Anti-Gravity and Copilot are
optional until you ask for those peers.

## License

MIT. The planning workflows retain required third-party notices under their
skill directories.
