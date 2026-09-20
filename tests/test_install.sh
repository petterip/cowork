#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

HOME="$tmp/home" CODEX_HOME="$tmp/custom-codex" \
  "$repo_root/install.sh" --agent codex >/dev/null

[[ "$(readlink -f "$tmp/custom-codex/cowork")" == "$repo_root" ]]
for skill in cowork cowork-plan cowork-build cowork-review cowork-continue cowork-status cowork-setup cowork-gemini cowork-copilot; do
  link="$tmp/custom-codex/skills/$skill"
  [[ -L "$link" ]]
  [[ "$(readlink -f "$link")" == "$repo_root/skills/$skill" ]]
done
[[ ! -e "$tmp/home/.codex" ]]

HOME="$tmp/home" CODEX_HOME="$tmp/custom-codex" \
  "$repo_root/install.sh" --agent opencode >/dev/null

for skill in cowork cowork-plan cowork-build cowork-review cowork-continue cowork-status cowork-setup cowork-gemini cowork-copilot; do
  link="$tmp/home/.config/opencode/skills/$skill"
  [[ -L "$link" ]]
  [[ "$(readlink -f "$link")" == "$repo_root/skills/$skill" ]]
done

HOME="$tmp/home" CODEX_HOME="$tmp/custom-codex" \
  "$repo_root/install.sh" --agent copilot >/dev/null

for skill in cowork cowork-plan cowork-build cowork-review cowork-continue cowork-status cowork-setup cowork-gemini cowork-copilot; do
  link="$tmp/home/.copilot/skills/$skill"
  [[ -L "$link" ]]
  [[ "$(readlink -f "$link")" == "$repo_root/skills/$skill" ]]
done

HOME="$tmp/home" CODEX_HOME="$tmp/custom-codex" \
  "$repo_root/install.sh" --agent copilot >/dev/null

HOME="$tmp/home" CODEX_HOME="$tmp/custom-codex" \
  "$repo_root/install.sh" --agent codex >/dev/null

HOME="$tmp/home-copilot-only" CODEX_HOME="$tmp/copilot-only" \
  "$repo_root/install.sh" --agent copilot >/dev/null
[[ "$(readlink -f "$tmp/copilot-only/cowork")" == "$repo_root" ]]
[[ -x "$tmp/copilot-only/cowork/scripts/resolve-model.sh" ]]
[[ ! -e "$tmp/home-copilot-only/.codex" ]]

mkdir -p "$tmp/collision/cowork"
if HOME="$tmp/home" CODEX_HOME="$tmp/collision" \
  "$repo_root/install.sh" --agent codex >/dev/null 2>&1; then
  printf '%s\n' 'Installer overwrote a foreign Cowork support directory.' >&2
  exit 1
fi

# Renaming the checkout leaves links that point at the previous clone name. The
# audit reports each problem without writing, --repair replaces them, and a
# dangling link this installer does not own stays a collision.
stale_home="$tmp/stale-home"
stale_codex="$tmp/stale-codex"
mkdir -p "$stale_codex/skills"
ln -s "$tmp/old/cowork-claude-codex/skills/cowork-plan" "$stale_codex/skills/cowork-plan"

if HOME="$stale_home" CODEX_HOME="$stale_codex" \
  "$repo_root/install.sh" --check --agent codex >"$tmp/check-before.txt" 2>&1; then
  printf '%s\n' 'Installer check passed while a stale Cowork link was present.' >&2
  exit 1
fi
rg -q '^Stale: ' "$tmp/check-before.txt"
rg -q '^Missing: ' "$tmp/check-before.txt"
[[ -L "$stale_codex/skills/cowork-plan" ]]
[[ ! -e "$stale_codex/cowork" ]]

if HOME="$stale_home" CODEX_HOME="$stale_codex" \
  "$repo_root/install.sh" --agent codex >/dev/null 2>&1; then
  printf '%s\n' 'Plain install replaced a stale Cowork link instead of reporting it.' >&2
  exit 1
fi

HOME="$stale_home" CODEX_HOME="$stale_codex" \
  "$repo_root/install.sh" --repair --agent codex >/dev/null
[[ "$(readlink -f "$stale_codex/skills/cowork-plan")" == "$repo_root/skills/cowork-plan" ]]
for skill in cowork cowork-plan cowork-build cowork-review cowork-continue cowork-status cowork-setup cowork-gemini cowork-copilot; do
  link="$stale_codex/skills/$skill"
  [[ "$(readlink -f "$link")" == "$repo_root/skills/$skill" ]]
done
HOME="$stale_home" CODEX_HOME="$stale_codex" \
  "$repo_root/install.sh" --check --agent codex >/dev/null

# The DSH skill root is `skills/` under DSH_AGENTS_HOME, which defaults to
# ~/.agents; that is the root a DeepSeek Harness session discovers skills from.
# A superseded legacy link is cleared from that root even when it dangles at the
# pre-rename clone.
mkdir -p "$tmp/agents/skills"
ln -s "$tmp/old/cowork-claude-codex/skills/claude-handoff" "$tmp/agents/skills/claude-handoff"
HOME="$stale_home" DSH_AGENTS_HOME="$tmp/agents" \
  "$repo_root/install.sh" --agent dsh >/dev/null
[[ ! -L "$tmp/agents/skills/claude-handoff" ]]
for skill in cowork cowork-plan cowork-build cowork-review cowork-continue cowork-status cowork-setup cowork-gemini cowork-copilot; do
  link="$tmp/agents/skills/$skill"
  [[ -L "$link" ]]
  [[ "$(readlink -f "$link")" == "$repo_root/skills/$skill" ]]
done

foreign_codex="$tmp/foreign-codex"
mkdir -p "$foreign_codex/skills"
ln -s "$tmp/elsewhere/skills/cowork-plan" "$foreign_codex/skills/cowork-plan"
if HOME="$stale_home" CODEX_HOME="$foreign_codex" \
  "$repo_root/install.sh" --repair --agent codex >/dev/null 2>&1; then
  printf '%s\n' 'Installer replaced a dangling link it does not own.' >&2
  exit 1
fi
[[ "$(readlink "$foreign_codex/skills/cowork-plan")" == "$tmp/elsewhere/skills/cowork-plan" ]]

printf '%s\n' 'Cowork installer contract: PASS'
