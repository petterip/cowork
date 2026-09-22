#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Cowork root resolution failed: %s\n' "$1" >&2
  exit 1
}

is_cowork_root() {
  local candidate=$1
  [[ -x "$candidate/scripts/cowork" ]] || return 1
  if [[ -f "$candidate/apm.yml" ]] \
    && awk '$1 == "name:" && $2 == "cowork" { found = 1 } END { exit found ? 0 : 1 }' "$candidate/apm.yml"; then
    return 0
  fi
  for manifest in "$candidate/plugin.json" "$candidate/.claude-plugin/plugin.json"; do
    if [[ -f "$manifest" ]] \
      && grep -Eq '"name"[[:space:]]*:[[:space:]]*"cowork"' "$manifest"; then
      return 0
    fi
  done
  return 1
}

if [[ -n "${COWORK_PLUGIN_ROOT:-}" ]]; then
  explicit_root=$(cd "$COWORK_PLUGIN_ROOT" 2>/dev/null && pwd -P) \
    || fail "COWORK_PLUGIN_ROOT does not exist: $COWORK_PLUGIN_ROOT"
  is_cowork_root "$explicit_root" \
    || fail "COWORK_PLUGIN_ROOT is not a Cowork package: $explicit_root"
  printf '%s\n' "$explicit_root"
  exit 0
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
plugin_root=$(cd "$script_dir/../../.." && pwd -P)
if is_cowork_root "$plugin_root"; then
  printf '%s\n' "$plugin_root"
  exit 0
fi

workspace_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
module_root="$workspace_root/apm_modules"
[[ -d "$module_root" ]] \
  || fail "no plugin root or APM module tree found from $workspace_root"

matches=()
while IFS= read -r cli; do
  candidate=${cli%/scripts/cowork}
  if is_cowork_root "$candidate"; then
    matches+=("$candidate")
  fi
done < <(find "$module_root" -mindepth 3 -maxdepth 5 -type f -path '*/scripts/cowork' -print | sort)

case ${#matches[@]} in
  1)
    printf '%s\n' "${matches[0]}"
    ;;
  0)
    fail "Cowork is not materialized below $module_root"
    ;;
  *)
    fail "multiple Cowork package roots found below $module_root"
    ;;
esac
