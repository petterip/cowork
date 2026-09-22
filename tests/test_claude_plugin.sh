#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
marketplace="$repo_root/.claude-plugin/marketplace.json"
plugin_root="$repo_root"
portable_manifest="$plugin_root/plugin.json"
apm_manifest="$plugin_root/apm.yml"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

[[ -f "$marketplace" ]]
[[ -f "$plugin_root/.claude-plugin/plugin.json" ]]
[[ -f "$portable_manifest" ]]
[[ -f "$apm_manifest" ]]
version=$(jq -r '.version' "$portable_manifest")
jq -e '.name == "cowork" and .plugins[0].name == "cowork" and .plugins[0].source == "."' "$marketplace" >/dev/null
jq -e --arg version "$version" '.owner.name == "Petteri Ponsimaa" and .metadata.version == $version and .plugins[0].version == $version and .plugins[0].author.name == "Petteri Ponsimaa"' "$marketplace" >/dev/null
jq -e --arg version "$version" '.name == "cowork" and .version == $version and .author.name == "Petteri Ponsimaa"' "$plugin_root/.claude-plugin/plugin.json" >/dev/null
jq -e '
  ."$schema" == "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
  and .name == "cowork"
  and .author.name == "Petteri Ponsimaa"
' "$portable_manifest" >/dev/null
python3 - "$apm_manifest" "$version" <<'PY'
import pathlib
import sys

manifest = pathlib.Path(sys.argv[1]).read_text()
version = sys.argv[2]
required = (
    "name: cowork\n",
    f"version: {version}\n",
    "includes: auto\n",
    "  - agent-skills\n",
    "  - claude\n",
    "  - codex\n",
    "  - copilot\n",
)
missing = [entry.rstrip() for entry in required if entry not in manifest]
if missing:
    raise SystemExit(f"Invalid apm.yml; missing: {', '.join(missing)}")
PY

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
rg -Fq 'scripts/cowork setup --refresh' "$plugin_root/commands/setup.md"
rg -Fq 'scripts/cowork resolve --peer codex' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'scripts/cowork resolve --model' "$plugin_root/skills/cowork-review/SKILL.md"
rg -Fq 'CODEX_ARGS=()' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'CODEX_ARGS+=(-m "$CODEX_MODEL")' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'CODEX_ARGS+=(-c "model_reasoning_effort=$CODEX_EFFORT")' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'codex exec ${BUILD_ACCESS[@]+"${BUILD_ACCESS[@]}"} ${CODEX_ARGS[@]+"${CODEX_ARGS[@]}"}' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'codex exec resume "$THREAD_ID" ${BUILD_ACCESS[@]+"${BUILD_ACCESS[@]}"} ${CODEX_ARGS[@]+"${CODEX_ARGS[@]}"}' "$plugin_root/skills/codex-build/SKILL.md"
rg -Fq 'scripts/cowork resolve --model' "$plugin_root/skills/cowork-review/SKILL.md"
rg -Fq 'scripts/cowork setup --refresh' "$repo_root/README.md"
rg -Fq 'No model names or versions are built into routing logic' "$repo_root/README.md"

for skill in plan build review continue status setup agy copilot; do
  [[ -f "$repo_root/skills/cowork-$skill/SKILL.md" ]]
done

# The entry skill is what a host without /cowork:* commands reads first, so it
# must name the one-shot launcher and refuse to turn advice into a job.
[[ -f "$plugin_root/skills/cowork/SKILL.md" ]]
rg -Fq 'invoke-peer-review.sh' "$plugin_root/skills/cowork/SKILL.md"
rg -Fq 'Read-only advice is not a job' "$plugin_root/skills/cowork/SKILL.md"

if rg -n '/cowork:(plan-with-docs|review-plan|handoff)' "$repo_root/README.md" "$repo_root/skills" "$plugin_root/commands"; then
  printf '%s\n' 'Shipped guidance references a removed public command.' >&2
  exit 1
fi

for skill_dir in "$plugin_root"/skills/*; do
  skill=${skill_dir##*/}
  [[ -f "$skill_dir/SKILL.md" ]]
  [[ -f "$skill_dir/apm.yml" ]]
  rg -q "^name: $skill$" "$skill_dir/SKILL.md"
  rg -q "^name: $skill$" "$skill_dir/apm.yml"
  rg -q "^version: $version$" "$skill_dir/apm.yml"
  awk -v expected="$version" '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && $0 == "metadata:" { in_metadata = 1; next }
    in_metadata && $0 ~ /^  version: / {
      actual = $0
      sub(/^  version: /, "", actual)
      found = (actual == expected)
      exit
    }
    in_metadata && $0 !~ /^  / { in_metadata = 0 }
    END { exit found ? 0 : 1 }
  ' "$skill_dir/SKILL.md"
done

if command -v apm >/dev/null 2>&1; then
  apm_project="$tmp/apm-project"
  mkdir -p "$apm_project"
  cat > "$apm_project/apm.yml" <<EOF
name: cowork-consumer-test
version: 1.0.0
description: Verify Cowork's unified APM package.
author: test
targets:
  - agent-skills
dependencies:
  apm:
    - $plugin_root
  mcp: []
includes: auto
scripts: {}
EOF
  (
    cd "$apm_project"
    apm install --target agent-skills >/dev/null
  )
  [[ "$(rg -c '^- repo_url:' "$apm_project/apm.lock.yaml")" == 1 ]]
  rg -q "^  version: $version$" "$apm_project/apm.lock.yaml"
  rg -q '^  package_type: skill_bundle$' "$apm_project/apm.lock.yaml"
  [[ -f "$apm_project/.agents/skills/cowork-plan/SKILL.md" ]]
  [[ -f "$apm_project/.agents/skills/cowork-setup/SKILL.md" ]]
  projected_resolver="$apm_project/.agents/skills/codex-claude-rally/scripts/resolve-cowork-root.sh"
  resolved_root=$(cd "$apm_project" && "$projected_resolver")
  [[ -x "$resolved_root/scripts/cowork" ]]
fi

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
  for skill in plan build review continue status setup agy copilot; do
    rg -q "^  cowork-$skill -" <<<"$discovered"
  done
fi

printf '%s\n' 'Cowork portable plugin contract: PASS'
