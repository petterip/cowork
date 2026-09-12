#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_root="$repo_root/skills"
command -v apm >/dev/null 2>&1 || {
  printf '%s\n' 'APM 0.30.0 is required; this contract must not silently skip.' >&2
  exit 1
}
command -v jq >/dev/null 2>&1
version=$(apm --version)
[[ "$version" == *'version 0.30.0 '* ]] || {
  printf 'Use the verified APM 0.30.0 toolchain (got %s).\n' "$version" >&2
  exit 1
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/source-package" "$tmp/source-consumer" "$tmp/pinned-consumer"

# Exercise the edited source, not only the older remote pins in skills/apm.yml.
{
  printf 'name: cowork-source-test\nversion: 1.0.0\ndependencies:\n  apm:\n'
  for skill_dir in "$package_root"/*; do
    [[ -f "$skill_dir/SKILL.md" ]] || continue
    printf '    - path: %s\n' "$(jq -Rn --arg path "$skill_dir" '$path')"
  done
} > "$tmp/source-package/apm.yml"

modes=(source pinned)
case "${1-}" in
  --source-only) modes=(source) ;;
  --help) printf '%s\n' 'usage: test_apm_package.sh [--source-only]'; exit 0 ;;
  '') ;;
  *) printf '%s\n' 'Unknown option; use --help.' >&2; exit 2 ;;
esac
for mode in "${modes[@]}"; do
  consumer="$tmp/$mode-consumer"
  source="$package_root"
  [[ "$mode" == source ]] && source="$tmp/source-package"
  (
    cd "$consumer"
    apm install "$source" --target copilot,claude,codex,agent-skills > install.log 2>&1 || {
      cat install.log >&2
      exit 1
    }
  )
  for target in .agents/skills .claude/skills; do
    installed="$consumer/$target"
    expected=0
    for skill_dir in "$package_root"/*; do
      [[ -f "$skill_dir/SKILL.md" ]] || continue
      skill=${skill_dir##*/}
      ((expected += 1))
      [[ -f "$installed/$skill/SKILL.md" ]]
      # Every source resource must survive deployment, with executable modes.
      while IFS= read -r -d '' resource; do
        relative=${resource#"$skill_dir"/}
        [[ -f "$installed/$skill/$relative" ]]
        if [[ -x "$resource" ]]; then [[ -x "$installed/$skill/$relative" ]]; fi
        if [[ "$mode" == source ]]; then cmp "$resource" "$installed/$skill/$relative"; fi
      done < <(find "$skill_dir" -type f -print0)
    done
    actual=$(find "$installed" -mindepth 2 -maxdepth 2 -name SKILL.md | wc -l | tr -d ' ')
    [[ "$actual" == "$expected" ]]
    # Resolve scripts outside their source checkout and without a plugin root.
    (
      cd "$consumer"
      for script in cowork-route invoke-peer-review resolve-model; do
        "$installed/cowork-runtime/scripts/$script.sh" --help >/dev/null
      done
      "$installed/codex-claude-rally/scripts/rallyctl.sh" --help >/dev/null
    )
  done
  printf 'Cowork APM %s contract: PASS (%s skills)\n' "$mode" "$actual"
done

package_version=$(sed -n 's/^version: "\(.*\)"$/\1/p' "$package_root/apm.yml")
plugin_version=$(jq -r '.version' "$repo_root/plugin.json")
if [[ -z "$package_version" || "$package_version" != "$plugin_version" ]]; then
  printf 'APM package version %s does not match plugin version %s.\n' \
    "${package_version:-<missing>}" "$plugin_version" >&2
  exit 1
fi
