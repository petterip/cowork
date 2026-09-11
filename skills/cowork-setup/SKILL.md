---
name: cowork-setup
description: Verify that Cowork prerequisites, authentication, full-access inheritance, and artifact storage are ready. Use before the first Cowork job or when delegation fails.
---

# Setup

Run `../codex-claude-rally/scripts/verify-environment.sh` relative to this
skill's real base directory after following any symlink, and report its exact
result. Do not change credentials.
A failed required check blocks Claude or
Codex delegation; restricted full-access status is informational unless the
user already authorized full access. Gemini (`agy`) and GitHub Copilot CLI
(`copilot`) are optional until requested. If Claude plugin list still shows
`cowork@cowork-claude-codex`, report that the shipped id is `cowork@cowork`
and do not uninstall or install without the user's request.

Model names never name CLIs, so availability is never checked with `which
<model-name>`: OpenAI models (GPT-x, Astra) run through the `codex` peer,
Claude models (Opus, Fable, Sonnet) through the `claude` peer, Gemini Flash
through `agy`, Copilot-hosted models through `copilot`. Answer "is <model>
available" from that peer's own model surface (`agy models`,
`copilot /model --list --json`; Codex has none — its configured default is the
authority and account auth decides which sibling slugs a real request
accepts), resolving the slug live rather than guessing.
