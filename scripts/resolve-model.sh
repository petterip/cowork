#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Cowork model resolution failed: %s\n' "$1" >&2
  exit 1
}

family=''
via=''
effort='medium'
query=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --family) [[ $# -ge 2 ]] || fail '--family requires a value.'; family=$2; shift 2 ;;
    --via) [[ $# -ge 2 ]] || fail '--via requires a value.'; via=$2; shift 2 ;;
    --effort) [[ $# -ge 2 ]] || fail '--effort requires a value.'; effort=$2; shift 2 ;;
    --query) [[ $# -ge 2 ]] || fail '--query requires a model family or name.'; query=$2; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ "$family" == gemini-flash || "$family" == auto || "$family" == named ]] ||
  fail 'family must be gemini-flash, auto, or named.'
[[ "$via" == agy || "$via" == copilot || "$via" == codex ]] ||
  fail 'via must be agy, copilot, or codex.'
[[ "$effort" =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]] || fail 'effort must be a CLI-safe level name.'
if [[ "$family" == named ]]; then
  [[ -n "$query" ]] || fail 'family named requires --query.'
  [[ "$via" == copilot || "$via" == codex ]] || fail 'family named is only valid via copilot or codex.'
elif [[ -n "$query" ]]; then
  fail '--query is only valid with family named.'
fi

if [[ "$family" != named && -n "${COWORK_MODEL-}" ]]; then
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
  local models json help
  help=$(copilot help config 2>/dev/null || true)
  models=$(awk '
    /^  `model`:/ { in_models = 1; next }
    in_models && /^    - "/ {
      value = $0
      sub(/^    - "/, "", value)
      sub(/".*$/, "", value)
      print value
      found = 1
      next
    }
    in_models && found { exit }
  ' <<<"$help")
  if [[ -n "$models" ]]; then
    printf '%s\n' "$models"
    return
  fi

  # Retain compatibility with CLI builds that exposed a JSON model picker.
  json=$(copilot /model --list --json 2>/dev/null || true)
  if [[ -n "$json" ]] && command -v jq >/dev/null 2>&1 &&
    jq -e 'type == "array" and length > 0' >/dev/null 2>&1 <<<"$json"; then
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

list_codex_slugs() {
  command -v codex >/dev/null 2>&1 || fail 'the Codex CLI (codex) is required.'
  command -v jq >/dev/null 2>&1 || fail 'jq is required to parse Codex model lists.'
  local json errors status=0
  errors=$(mktemp)
  trap 'rm -f "$errors"' RETURN
  json=$(codex debug models 2>"$errors") || status=$?
  if (( status != 0 )) || [[ -z "$json" ]]; then
    printf 'codex debug models failed (exit %s):\n' "$status" >&2
    cat "$errors" >&2
    rm -f "$errors"
    fail 'could not list Codex models; pass an exact --model slug.'
  fi
  rm -f "$errors"
  jq -r '.. | objects | (.slug? // .id? // empty)' <<<"$json" | sort -u
}

pick_named() {
  local name=$1
  shift
  local slugs=$*
  local token matches
  matches=$slugs
  while IFS= read -r token; do
    [[ -n "$token" ]] || continue
    matches=$(printf '%s\n' "$matches" | grep -iF -- "$token" || true)
  done < <(printf '%s\n' "$name" | tr '[:upper:]' '[:lower:]' | grep -Eo '[a-z]+|[0-9]+')
  picked=$(printf '%s\n' "$matches" | sed '/^$/d' | sort -V | tail -n1)
  [[ -n "$picked" ]] || fail "$via listed no model matching '$name'; pass an exact --model slug."
  printf '%s\n' "$picked"
}

if [[ "$family" == named ]]; then
  if [[ "$via" == copilot ]]; then
    slugs=$(list_copilot_slugs)
  else
    slugs=$(list_codex_slugs)
  fi
  pick_named "$query" "$slugs"
  exit 0
fi

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
