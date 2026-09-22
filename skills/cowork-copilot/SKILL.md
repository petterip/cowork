---
name: cowork-copilot
metadata:
  version: 1.6.0
description: Delegate cowork work to GitHub Copilot CLI. Use only when the user explicitly asks for Copilot; otherwise preserve the default pairing.
---

# GitHub Copilot peer

Use the standalone `copilot` CLI, not the older `gh copilot` extension. Resolve
`RALLY_SCRIPTS` to `../codex-claude-rally/scripts` from this skill's real
directory, then run
`COWORK_PLUGIN_ROOT=$("$RALLY_SCRIPTS/resolve-cowork-root.sh")`.

For reviews, use the shared router rather than constructing a command:

```bash
"$COWORK_PLUGIN_ROOT/scripts/cowork" setup
"$COWORK_PLUGIN_ROOT/scripts/cowork-route.sh" review \
  '--peer copilot [--model <exact-id>|--model-name <user text>] [--effort <level>] [--base <ref>] [focus]'
```

Rules:

- Copilot remains the peer regardless of the requested model.
- Supplied model text resolves from setup's live catalog. Without a model, use
  Copilot's native default.
- Pass effort only when the user requested it; setup records the supported
  option name.
- Reviews are read-only. Never use `--allow-all`, `--yolo`, or broad Git tool
  permissions. The router supplies the bounded diff and allowed commands.
- Verify the report and confirm the working tree is unchanged.

For build or continuation, follow `cowork-build` or `cowork-continue`; those
workflows call `scripts/invoke-peer-work.sh` with provider `copilot`.
