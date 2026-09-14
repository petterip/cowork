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

### APM

Use **APM 0.30.0** for the verified source install path. Check
`apm --version`; upgrade with the package manager that installed APM.
The `skills/` collection installs all 15 skills, including shared runtime
scripts, Rally tools, and planning references. Pin the collection revision:

```yaml
targets: [copilot, claude, codex, agent-skills]
dependencies:
  apm:
    - git: https://github.com/petterip/cowork.git
      path: skills
      ref: <40-character-commit-sha>
```

Run `apm install` from the consuming repository. Select only the hosts you
use; retain `agent-skills` for the shared `.agents/skills/` location. Claude
also receives `.claude/skills/`. Commit the consumer manifest and lockfile.
The collection pins its sibling skill revisions; updating those skills requires
updating the collection pins as well as the consumer's collection revision.

APM installs skills, not the native `/cowork:*` commands. Invoke
`cowork-plan`, `cowork-build`, `cowork-review`, `cowork-continue`,
`cowork-status`, or `cowork-setup` by name in your agent. Claude Code defaults
to a Codex peer; Codex and Copilot default to Claude. Explicit peer choices
use the selected adapter. Avoid installing the same skills through both APM
and the native plugin in one host, which can create duplicate entrypoints.

Before a first job, authenticate the selected CLIs and run `cowork-setup`.
Before launching a peer, export `COWORK_DATA_CLASSIFICATION` as `public`,
`internal`, `confidential`, or `restricted`, and list the approved peer CLIs in
the exported, comma-separated `COWORK_APPROVED_DESTINATIONS` (for example,
`claude,codex,agy`, with no spaces). Default review and transfer use `codex`;
`--gemini` uses `agy`; `--copilot` uses `copilot`; Claude handoff and Rally use
`claude`. Confidential and
restricted payloads also require `COWORK_REDACTION_CONFIRMED=true` after the
payload has been reduced to the approved minimum. Missing or mismatched values
block runtime-routed launches. Skill-directed Claude and Codex launches run the
same gate before preparing their peer prompt. Local status inspection is exempt.
For an installation-only check that does not launch a model:

```bash
.agents/skills/cowork-runtime/scripts/cowork-route.sh --help
.agents/skills/codex-claude-rally/scripts/rallyctl.sh --help
```

Bash, Git, `jq`, and `sha256sum` or `shasum` are required. Use a POSIX
shell on macOS/Linux or WSL. APM installs neither peer CLIs nor credentials.
If skills are missing, check the **consumer's** targets and restart/reload the
host. If scripts are missing, reinstall the complete collection with the
verified APM version; do not copy a single public skill without its siblings.

Use repository/tag installation for APM. In APM 0.30.0, archives contain the
scripts but archive installation drops executable permissions; Cowork calls
sibling scripts directly and cannot run from that restore. Native plugin
installation remains a separate supported path. Both source and
installed-runtime contracts are checked by `tests/test_apm_package.sh`; this
requires network access to the pinned public repository and fails if APM is
absent.

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
tests/test_apm_package.sh
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
