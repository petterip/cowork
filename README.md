# Cowork

Use one model to plan, build, review, or continue work with another. Cowork
selects the direction from the environment and keeps material work bounded and
verifiable. Claude, Codex, Gemini Flash, and GitHub Copilot are peers.

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
default other model. Ask for Gemini or Copilot when you want those peers
instead. Model names are not peer names: Astra is an OpenAI model inside the
Codex peer; Opus and Fable are Claude models inside the rally worker
(`claude --model fable`); Gemini Flash is a model family inside `agy`. Resolve
a requested model name to its peer CLI and that peer's own model surface —
never probe for a binary named after the model.

Gemini Flash is an explicit opt-in: `/cowork:review --gemini` uses the
Antigravity CLI (`agy`) and resolves the current Flash slug from `agy models`.
`--copilot` uses the GitHub Copilot CLI (`copilot` from `@github/copilot`).
`--gemini --copilot` resolves the current Gemini Flash id from Copilot's live
model list. Pass `--model <slug>` or set `COWORK_MODEL` only when you need an
exact id; the plugin does not keep versions in source.

`plan` also covers documentation-aware planning and review of an existing
plan. `build` requires an approved plan and independent proof. `review` never
edits. `continue` transfers the current context without pretending it is a
verified build.

## Install

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

GitHub Copilot CLI skills from a clone:

```bash
./install.sh --agent copilot
```

Install Claude Code and Codex from a clone:

```bash
./install.sh --agent both
```

Install everywhere (Claude Code, Codex, opencode, and Copilot skills):

```bash
./install.sh --agent all
```

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
skills/codex-claude-rally/scripts/test_contract.sh
```

Check the authenticated local environment separately before a real job:

```bash
skills/codex-claude-rally/scripts/verify-environment.sh
```

The Claude subscription check blocks known API/provider authentication and
requires a first-party subscription login. Claude Code cannot expose whether
optional account-level usage credits are enabled. Gemini and Copilot are
optional until you ask for those peers.

## License

MIT. The planning workflows retain required third-party notices under their
skill directories.
