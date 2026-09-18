#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
marketplace="$repo_root/.claude-plugin/marketplace.json"
plugin_root="$repo_root"
portable_manifest="$plugin_root/plugin.json"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

[[ -f "$marketplace" ]]
[[ -f "$plugin_root/.claude-plugin/plugin.json" ]]
[[ -f "$portable_manifest" ]]
version=$(jq -r '.version' "$portable_manifest")
jq -e '.name == "cowork" and .plugins[0].name == "cowork" and .plugins[0].source == "."' "$marketplace" >/dev/null
jq -e --arg version "$version" '.owner.name == "Petteri Ponsimaa" and .metadata.version == $version and .plugins[0].version == $version and .plugins[0].author.name == "Petteri Ponsimaa"' "$marketplace" >/dev/null
jq -e --arg version "$version" '.name == "cowork" and .version == $version and .author.name == "Petteri Ponsimaa"' "$plugin_root/.claude-plugin/plugin.json" >/dev/null
jq -e '
  ."$schema" == "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
  and .name == "cowork"
  and .author.name == "Petteri Ponsimaa"
' "$portable_manifest" >/dev/null

wrong_identity="Petteri Piir"'onen'
if rg --hidden -n -g '!.git/**' "$wrong_identity" "$repo_root"; then
  printf '%s\n' 'Incorrect author identity remains in the repository.' >&2
  exit 1
fi

for command in plan build review continue status setup; do
  [[ -f "$plugin_root/commands/$command.md" ]]
done

for legacy in plan-with-docs review-plan handoff; do
  [[ ! -e "$plugin_root/commands/$legacy.md" ]]
done

if rg --files "$plugin_root/commands" | rg -q '/[^/]*grill[^/]*$'; then
  printf '%s\n' 'Legacy grill command remains public.' >&2
  exit 1
fi

rg -Fq 'cowork-route.sh review' "$plugin_root/commands/review.md"
rg -Fq '/codex:rescue' "$plugin_root/commands/build.md"
rg -Fq 'Bash(*resolve-model.sh:*)' "$plugin_root/commands/continue.md"
rg -Fq 'cowork-route.sh transfer' "$plugin_root/commands/continue.md"
rg -Fq 'claude plugin list' "$plugin_root/commands/setup.md"
rg -Fq 'fallback' "$plugin_root/commands/setup.md"
rg -Fq -- '--family named --via codex' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'models published after' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'including families published after' "$plugin_root/skills/cowork-review/SKILL.md"
rg -Fq 'CODEX_ARGS=()' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'CODEX_ARGS+=(-m "$CODEX_MODEL")' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'CODEX_ARGS+=(-c "model_reasoning_effort=$CODEX_EFFORT")' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'codex exec "${BUILD_ACCESS[@]}" "${CODEX_ARGS[@]}"' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'codex exec resume "$THREAD_ID" "${BUILD_ACCESS[@]}" "${CODEX_ARGS[@]}"' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'claude --model' "$plugin_root/skills/cowork-review/SKILL.md"
rg -Fq 'Review the changes made with cowork using Opus' "$repo_root/README.md"
rg -Fq 'GPT-6 Astra at low reasoning effort' "$repo_root/README.md"

for skill in plan build review continue status setup gemini copilot; do
  [[ -f "$repo_root/skills/cowork-$skill/SKILL.md" ]]
done

if rg -n '/cowork:(plan-with-docs|review-plan|handoff)' "$repo_root/README.md" "$repo_root/skills" "$plugin_root/commands"; then
  printf '%s\n' 'Shipped guidance references a removed public command.' >&2
  exit 1
fi

for skill_dir in "$plugin_root"/skills/*; do
  skill=${skill_dir##*/}
  [[ -f "$skill_dir/SKILL.md" ]]
  rg -q "^name: $skill$" "$skill_dir/SKILL.md"
done

for script in "$plugin_root"/scripts/*.sh "$plugin_root"/skills/codex-claude-rally/scripts/*.sh; do
  [[ -x "$script" ]]
done

for resource in \
  skills/codex-claude-rally/references/job-protocol.md \
  skills/grill-with-docs-codex/ADR-FORMAT.md \
  skills/grill-with-docs-codex/CONTEXT-FORMAT.md; do
  [[ -f "$plugin_root/$resource" ]]
done

if rg -n 'plugins/cowork/(workflows|skills)|CLAUDE_PLUGIN_ROOT/workflows' "$repo_root/README.md" "$plugin_root/commands" "$plugin_root/skills"; then
  printf '%s\n' 'Legacy plugin workflow paths remain.' >&2
  exit 1
fi

if command -v claude >/dev/null 2>&1; then
  claude plugin validate "$plugin_root" >/dev/null
fi

if command -v copilot >/dev/null 2>&1; then
  COPILOT_HOME="$tmp/copilot" copilot plugin marketplace add "$plugin_root" >/dev/null
  COPILOT_HOME="$tmp/copilot" copilot plugin install cowork@cowork >/dev/null
  discovered=$(COPILOT_HOME="$tmp/copilot" copilot skill list)
  for skill in plan build review continue status setup gemini copilot; do
    rg -q "^  cowork-$skill -" <<<"$discovered"
  done
fi

printf '%s\n' 'Cowork portable plugin contract: PASS'
