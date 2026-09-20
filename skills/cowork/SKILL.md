---
name: cowork
description: Route a request to a second model without reading the protocol first. Use when the user asks to use Cowork, or asks another model (Opus, Fable, Gemini, Codex, Copilot) to review, challenge, explain, or advise on material that can go in a prompt; use the build and rally skills instead when the work must be built, resumed, or audited across sessions.
---

# Cowork entry point

Follow [the shared delegation contract](../codex-claude-rally/references/delegation.md)
from this skill's resolved directory (follow symlinks). Resolve
`COWORK_PLUGIN_ROOT` to the plugin root two directories above this skill's real
base directory after following any symlink.

This is the front door. Choose the cheapest route that satisfies the request
instead of reading every workflow first.

## Choose the route

| Request                                                    | Route                                       |
| ---------------------------------------------------------- | ------------------------------------------- |
| A second opinion on material you can put in a prompt        | `scripts/invoke-peer-review.sh`             |
| Review of the current diff with the default peer            | `scripts/cowork-route.sh review …`          |
| An independent build, or work that must be resumed or audit | `cowork-build`, `codex-claude-rally`        |
| Continue in the other model                                 | `cowork-continue`                           |
| What is running, blocked, or resumable                      | `cowork-status`                             |
| Environment readiness                                       | `cowork-setup`, `scripts/cowork-doctor.sh`  |

Read-only advice is not a job: never create a rally manifest, worktree, or
worker for "what does Opus think of this". That machinery exists for writes and
resumption, and it costs far more than the answer.

## One call

```bash
"$COWORK_PLUGIN_ROOT/scripts/invoke-peer-review.sh" <peer> <model|auto> \
  --prompt-file /tmp/request.md
```

- **Peer vs model.** Peers are CLIs; model names are not peer names. Opus and
  Fable are Claude models on the `claude` peer, Gemini Flash is on `agy`, and
  Copilot-hosted families are on `copilot`. When a request names both, the peer
  wins. Never probe for a binary named after a model.
- **Coverage.** `invoke-peer-review.sh` covers `claude`, `agy`, and `copilot`.
  OpenAI/Codex models use the Codex peer through `cowork-review` or
  `codex-review`, not this launcher.
- **Model.** Pass `auto` unless the user named an exact model. `auto` resolves
  through `scripts/resolve-model.sh` against the selected peer's live surface
  (`claude` → its current Opus alias, `agy` → the newest Gemini Flash,
  `copilot` → its own default). Never hard-code a generation.
- **Effort.** `--effort medium` by default and `high` for adversarial
  challenges. Each peer validates the level against its own surface; never
  claim an effort that the invocation did not enforce.
- **Claude authentication.** The `claude` peer runs the subscription gate and
  fails closed under API-key or cloud-provider credentials, so a "Claude review"
  is always the first-party peer that was requested.
- **Material.** Put the diff, plan, or source in the prompt. A review runs from
  a scratch directory and cannot read the repository, so a prompt that describes
  the change instead of containing it produces narration, not review.
- **Size.** Past ~120 KB the prompt goes to `agy` on stdin; over 1 MB it is
  refused rather than truncated. Narrow the scope instead.

## After the call

- The report is advisory input, never acceptance. Verify every claim against
  the source before acting on it.
- Reviews are read-only. Confirm `git status --porcelain` is unchanged and
  investigate any new modification before trusting the findings.
- The initiating model owns the fixes; the peer never edits the reviewed tree.
