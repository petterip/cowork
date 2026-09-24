---
name: cowork
metadata:
  version: 1.6.0
description: Route a request to a second model without reading the protocol first. Use when the user asks to use Cowork or asks another peer/model to review, challenge, explain, or advise; use the build and rally skills when work must be built, resumed, or audited across sessions.
---

# Cowork entry point

Resolve `RALLY_SCRIPTS` to `../codex-claude-rally/scripts` from this skill's
real directory, then run
`COWORK_PLUGIN_ROOT=$("$RALLY_SCRIPTS/resolve-cowork-root.sh")`. This supports
both a native plugin and skills projected from one APM package.

For a read-only second opinion, do not read the build, rally, or provider
protocols. Use the cached machine interface:

Read-only advice is not a job; do not create a worktree or durable worker.

```bash
"$COWORK_PLUGIN_ROOT/scripts/cowork" setup
"$COWORK_PLUGIN_ROOT/scripts/cowork" resolve --peer <peer> [--model "<user text>"] --json
```

Then call:

```bash
"$COWORK_PLUGIN_ROOT/scripts/invoke-peer-review.sh" <peer> <resolved-id|auto> \
  --prompt-file <request>
```

Rules:

- A peer is a CLI. A model name is opaque user data.
- With a selected peer, pass unknown or ambiguous model names unchanged to its
  CLI. Catalogs are alias hints, not allowlists; never substitute model versions.
- An explicit peer wins. Without one, use `cowork resolve --model`; proceed
  only when one peer/id matches.
- If the user supplied no model, pass `auto`; the launcher omits the model
  option and lets the peer use its native default.
- Pass effort only when the user requested it.
- Put all review material in the prompt. Reviews are read-only and advisory.
- Verify findings against source and confirm the working tree is unchanged.

Use `cowork-review` for repository diffs, `cowork-build` for implementation,
`cowork-continue` for handoff, and `cowork-status` for durable jobs.
