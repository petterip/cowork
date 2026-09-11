#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_root="$repo_root/skills"
command -v apm >/dev/null 2>&1 || {
  printf '%s\n' 'APM package test skipped: apm is not installed.'
  exit 0
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

(
  cd "$tmp"
  apm install "$package_root" --target agent-skills --no-policy >/dev/null
)

installed="$tmp/.agents/skills"
expected=0
for skill_dir in "$package_root"/*; do
  [[ -f "$skill_dir/SKILL.md" ]] || continue
  skill=${skill_dir##*/}
  ((expected += 1))
  [[ -f "$installed/$skill/SKILL.md" ]]
done

actual=$(find "$installed" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
[[ "$actual" == "$expected" ]]
package_version=$(sed -n 's/^version: "\(.*\)"$/\1/p' "$package_root/apm.yml")
plugin_version=$(jq -r '.version' "$repo_root/plugin.json")
if [[ -z "$package_version" || "$package_version" != "$plugin_version" ]]; then
  printf 'APM package version %s does not match plugin version %s.\n' \
    "${package_version:-<missing>}" "$plugin_version" >&2
  exit 1
fi
for script in "$installed"/cowork-runtime/scripts/*.sh; do
  [[ -x "$script" ]]
done

printf 'Cowork APM package contract: PASS (%s skills)\n' "$actual"
