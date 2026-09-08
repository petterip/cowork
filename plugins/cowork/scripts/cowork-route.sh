#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Cowork routing failed: %s\n' "$1" >&2
  exit 1
}

[[ $# -ge 1 ]] || fail 'usage: cowork-route.sh <review|adversarial-review|transfer|status> [arguments]'
action=$1
arguments=${2:-}
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

resolve_official_runtime() {
  local root candidate
  if [[ -n "${COWORK_CODEX_PLUGIN_ROOT-}" ]]; then
    root=$COWORK_CODEX_PLUGIN_ROOT
  else
    command -v claude >/dev/null 2>&1 || return 1
    claude plugin list 2>/dev/null | grep -Fq 'codex@openai-codex' || return 1
    root=''
    while IFS= read -r candidate; do root=$candidate; done < <(
      find "$HOME/.claude/plugins/cache/openai-codex/codex" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V
    )
  fi
  [[ -n "$root" && -f "$root/scripts/codex-companion.mjs" ]] || return 1
  printf '%s\n' "$root/scripts/codex-companion.mjs"
}

runtime=$(resolve_official_runtime || true)
case "$action" in
  review|adversarial-review)
    read -r -a words <<<"$arguments"
    review_args=()
    focus=()
    gemini_requested=0
    copilot_requested=0
    explicit_model=''
    index=0
    while (( index < ${#words[@]} )); do
      case "${words[$index]}" in
        --wait|--background) ((index += 1)) ;;
        --gemini) gemini_requested=1; ((index += 1)) ;;
        --copilot) copilot_requested=1; ((index += 1)) ;;
        --model=*)
          explicit_model=${words[$index]#--model=}
          [[ -n "$explicit_model" ]] || fail '--model requires a slug.'
          ((index += 1))
          ;;
        --model)
          (( index + 1 < ${#words[@]} )) || fail '--model requires a slug.'
          explicit_model=${words[$((index + 1))]}
          ((index += 2))
          ;;
        --base=*)
          review_args+=(--base "${words[$index]#--base=}")
          ((index += 1))
          ;;
        --base)
          (( index + 1 < ${#words[@]} )) || fail '--base requires a ref.'
          review_args+=(--base "${words[$((index + 1))]}")
          ((index += 2))
          ;;
        *) focus+=("${words[$index]}"); ((index += 1)) ;;
      esac
    done
    if [[ -n "$explicit_model" ]] && (( !gemini_requested && !copilot_requested )); then
      fail 'pass --gemini or --copilot with --model; the plugin does not pin a peer from a slug alone.'
    fi
    if (( gemini_requested || copilot_requested )); then
      via=agy
      family=gemini-flash
      effort=medium
      (( copilot_requested )) && via=copilot
      if (( copilot_requested && !gemini_requested )); then
        family=auto
      fi
      [[ "$action" == adversarial-review ]] && effort=high
      prompt='Review the current code or diff as an independent, read-only reviewer.'
      if [[ "$action" == adversarial-review ]]; then
        prompt='Adversarially challenge the current code or diff as an independent, read-only reviewer: hunt for failure scenarios that break it.'
      fi
      if [[ ${#review_args[@]} -gt 0 ]]; then
        prompt+=" Review the diff against the recorded base arguments: ${review_args[*]}."
      else
        prompt+=' Review the uncommitted changes.'
      fi
      if [[ ${#focus[@]} -gt 0 ]]; then
        prompt+=" Focus: ${focus[*]}."
      fi
      prompt+=' Do not modify files. Report findings with file paths and concrete failure scenarios.'
      if [[ -n "$explicit_model" ]]; then
        model=$explicit_model
      else
        model=$("$script_dir/resolve-model.sh" --family "$family" --via "$via" --effort "$effort")
      fi
      exec "$script_dir/invoke-peer-review.sh" "$via" "$model" "$prompt"
    fi
    if [[ -n "$runtime" ]]; then
      exec node "$runtime" "$action" "$arguments"
    fi
    [[ "$action" == review ]] || fail 'adversarial review requires codex@openai-codex.'
    [[ ${#review_args[@]} -gt 0 ]] || review_args=(--uncommitted)
    if [[ ${#focus[@]} -gt 0 ]]; then
      exec codex review "${review_args[@]}" "${focus[*]}"
    fi
    exec codex review "${review_args[@]}"
    ;;
  transfer|status)
    [[ -n "$runtime" ]] || exit 2
    exec node "$runtime" "$action" "$arguments"
    ;;
  *) fail "unsupported action: $action" ;;
esac
