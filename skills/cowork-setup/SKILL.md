---
name: cowork-setup
metadata:
  version: 1.6.0
description: Verify that Cowork prerequisites, authentication, full-access inheritance, and artifact storage are ready. Use before the first Cowork job or when delegation fails.
---

# Setup

Resolve `RALLY_SCRIPTS` to `../codex-claude-rally/scripts` from this skill's
real directory, then run:

```bash
COWORK_PLUGIN_ROOT=$("$RALLY_SCRIPTS/resolve-cowork-root.sh")
"$COWORK_PLUGIN_ROOT/scripts/cowork" setup --refresh
```

This is the only setup discovery path. It finds installed peer CLIs, checks
whether each executable is usable, reads live model catalogs where the peer
publishes one, detects supported effort flags, and writes a compact capability
manifest outside the repository. Report its exact result. Do not install tools,
change credentials, or repair links unless the user asks.

For a later readiness check, use `scripts/cowork doctor`. For machine-readable
setup data, use `scripts/cowork setup --json`. Never probe for a binary named
after a model and never infer a peer from a model table embedded in this skill.
