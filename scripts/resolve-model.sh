#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Cowork model resolution failed: %s\n' "$1" >&2
  exit 1
}

family=''
via=''
effort='medium'
while [[ $# -gt 0 ]]; do
  case "$1" in
    --family) [[ $# -ge 2 ]] || fail '--family requires a value.'; family=$2; shift 2 ;;
    --via) [[ $# -ge 2 ]] || fail '--via requires a value.'; via=$2; shift 2 ;;
    --effort) [[ $# -ge 2 ]] || fail '--effort requires a value.'; effort=$2; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ "$family" == gemini-flash || "$family" == auto ]] || fail 'family must be gemini-flash or auto.'
[[ "$via" == agy || "$via" == copilot ]] || fail 'via must be agy or copilot.'
[[ "$effort" == low || "$effort" == medium || "$effort" == high ]] || fail 'effort must be low, medium, or high.'

if [[ -n "${COWORK_MODEL-}" ]]; then
  printf '%s\n' "$COWORK_MODEL"
  exit 0
fi

pick_latest() {
  local pattern=$1
  local match
  match=$(grep -E "$pattern" | sort -V | tail -n1 || true)
  printf '%s' "$match"
}

list_agy_slugs() {
  command -v agy >/dev/null 2>&1 || fail 'the Antigravity CLI (agy) is required for Gemini.'
  local errors output status=0
  errors=$(mktemp)
  trap 'rm -f "$errors"' RETURN
  # An auth or network failure must not read as "this account has no Flash
  # model": the CLI's own words are the only useful diagnosis.
  output=$(agy models 2>"$errors") || status=$?
  if (( status != 0 )) || [[ -z "$output" ]]; then
    printf 'agy models failed (exit %s):\n' "$status" >&2
    cat "$errors" >&2
    rm -f "$errors"
    fail 'could not list Gemini models; sign in with an interactive `agy` run, or set COWORK_MODEL.'
  fi
  rm -f "$errors"
  printf '%s\n' "$output" | awk '{print $1}' | sed '/^$/d'
}

list_copilot_slugs() {
  command -v copilot >/dev/null 2>&1 || fail 'the GitHub Copilot CLI (copilot) is required.'
  command -v jq >/dev/null 2>&1 || fail 'jq is required to parse Copilot model lists.'
  local json help
  json=$(copilot /model --list --json 2>/dev/null || true)
  if [[ -n "$json" ]] && jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$json"; then
    jq -r '.[].id' <<<"$json"
    return
  fi
  help=$(copilot --help 2>/dev/null || true)
  if printf '%s\n' "$help" | grep -Eq 'gemini-[0-9]'; then
    printf '%s\n' "$help" | grep -Eo 'gemini-[0-9]+([.][0-9]+)*-flash(-[a-z]+)?'
    return
  fi
  fail 'Copilot did not report a model list; pass --model or set COWORK_MODEL.'
}

if [[ "$family" == auto ]]; then
  [[ "$via" == copilot ]] || fail 'family auto is only valid via copilot.'
  printf '%s\n' auto
  exit 0
fi

if [[ "$via" == agy ]]; then
  slugs=$(list_agy_slugs)
  picked=$(printf '%s\n' "$slugs" | pick_latest "^gemini-[0-9]+([.][0-9]+)*-flash-${effort}$")
  if [[ -z "$picked" ]]; then
    picked=$(printf '%s\n' "$slugs" | pick_latest '^gemini-[0-9]+([.][0-9]+)*-flash$')
  fi
  [[ -n "$picked" ]] || fail "agy models listed no Gemini Flash slug for effort ${effort}."
  # Newest by version, never a pinned generation: the account's model list is
  # the authority, and it changes without notice.
  printf '%s\n' "$picked"
  exit 0
fi

slugs=$(list_copilot_slugs)
picked=$(printf '%s\n' "$slugs" | pick_latest '^gemini-[0-9]+([.][0-9]+)*-flash(-[a-z]+)?$')
[[ -n "$picked" ]] || fail 'Copilot listed no Gemini Flash model; pass --model or set COWORK_MODEL.'
printf '%s\n' "$picked"
