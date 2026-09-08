# Cowork Claude–Codex

Use one model to plan, build, review, or continue work with the other. Cowork
selects the direction from the environment and keeps material work bounded and
verifiable.

## Commands

| Goal                        | Claude Code        | Codex             |
| --------------------------- | ------------------ | ----------------- |
| Plan before coding          | `/cowork:plan`     | `cowork-plan`     |
| Build an approved plan      | `/cowork:build`    | `cowork-build`    |
| Review current work         | `/cowork:review`   | `cowork-review`   |
| Continue in the other model | `/cowork:continue` | `cowork-continue` |
| Show jobs                   | `/cowork:status`   | `cowork-status`   |
| Check setup                 | `/cowork:setup`    | `cowork-setup`    |

In Claude Code, Codex is the other model. In Codex, Claude is the other model.
Gemini 3.8 Flash is an explicit opt-in only: when the user asks for Gemini,
the second-model role goes to the Antigravity CLI (`agy`, ≥ 1.1.25) running
`gemini-3.8-flash-medium` (see the `cowork-gemini` skill). In
`/cowork:review`, pass `--gemini` in the arguments.

`plan` also covers documentation-aware planning and review of an existing
plan. `build` requires an approved plan and independent proof. `review` never
edits. `continue` transfers the current context without pretending it is a
verified build.

## Install

Claude Code:

```text
/plugin marketplace add petterip/cowork-claude-codex
/plugin install cowork@cowork-claude-codex
/reload-plugins
```

Codex:

```bash
./install.sh --agent codex
```

opencode:

```bash
./install.sh --agent opencode
```

Install both from a clone:

```bash
./install.sh --agent both
```

Install everywhere (Claude Code, Codex, and opencode):

```bash
./install.sh --agent all
```

The official `codex@openai-codex` Claude Code plugin is optional. When present,
Cowork uses its review, adversarial-review, status, and session-transfer paths.
Without it, normal reviews use the local Codex CLI; `continue` creates a fresh
Codex handoff, and official-plugin-only features report that requirement.

## How material work is handled

- Read-only work runs as a bounded second-model review.
- Write jobs use an isolated worktree created from the recorded source `HEAD`
  and explicit allowed paths. The source checkout may be dirty; staged,
  unstaged, and untracked user work stays local and is not copied into the
  worker. Hand-back must apply-check rather than overwrite local work.
- Requests, responses, reviews, and state transitions are durable artifacts.
- The initiating model verifies the diff and proof before acceptance.
- Commits, pushes, deployments, and credential changes remain human-gated.

Artifacts live outside the checkout:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/cowork-claude-codex/jobs/<job-id>/
```

## Verify the package

```bash
tests/test_claude_plugin.sh
tests/test_router.sh
tests/test_install.sh
skills/codex-claude-rally/scripts/test_contract.sh
```

Check the authenticated local environment separately before a real job:

```bash
skills/codex-claude-rally/scripts/verify-environment.sh
```

The Claude subscription check blocks known API/provider authentication and
requires a first-party subscription login. Claude Code cannot expose whether
optional account-level usage credits are enabled.

## License

MIT. The planning workflows retain required third-party notices under their
skill directories.
