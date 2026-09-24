---
name: cowork-review
metadata:
  version: 1.6.0
description: Ask a second model to independently review the current Codex work. Use for code, diff, design, security, or regression review when a second model should challenge completed or in-progress changes without editing them.
---

# Review

Resolve `RALLY_SCRIPTS` to `../codex-claude-rally/scripts` from this skill's
real directory, then run
`COWORK_PLUGIN_ROOT=$("$RALLY_SCRIPTS/resolve-cowork-root.sh")`. Do not read
the durable-job protocol for an ordinary review.

Determine the exact review scope:

- Working tree: staged, unstaged, and untracked changes.
- `--base <ref>`: committed tracked diff from that ref through `HEAD`; exclude
  unrelated working-tree and untracked changes.

Route the review through the single entry point:

```bash
"$COWORK_PLUGIN_ROOT/scripts/cowork" setup
"$COWORK_PLUGIN_ROOT/scripts/cowork-route.sh" review \
  '--peer <peer> [--model <exact-id>|--model-name <user text>] [--effort <level>] [--base <ref>] [focus]'
```

Model and peer rules:

- An explicitly requested peer always wins.
- Treat model text as opaque. `--model` is an exact id; `--model-name` resolves
  through the cached catalog using whole version numbers. With a selected peer,
  unmatched or ambiguous names pass unchanged to the CLI; never substitute a
  different version or reject a model because it is absent from the catalog.
- Without an explicit peer, use `scripts/cowork resolve --model` and proceed
  only if exactly one peer/id matches.
- Without a model, omit model selection and use the peer's native default.
- Pass effort only when requested.
- For the local Claude peer, never use `--cloud`; no remote session or
  subagent mode may stand in for the requested local peer.

The router embeds the diff with Git text conversion disabled and constrains
the peer to read-only review. Verify every finding against source, run focused
proof when practical, and confirm `git status --porcelain` is unchanged.
