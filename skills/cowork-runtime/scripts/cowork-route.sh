#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Cowork routing failed: %s\n' "$1" >&2
  exit 1
}

if [[ "${1-}" == --help ]]; then
  printf '%s\n' 'usage: cowork-route.sh <review|adversarial-review|transfer|status> [arguments]'
  exit 0
fi

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
    if (( gemini_requested && copilot_requested )); then
      fail '--gemini cannot be combined with --copilot.'
    fi
    if [[ -n "$explicit_model" ]] && (( !gemini_requested && !copilot_requested )); then
      fail 'pass --gemini or --copilot with --model; the plugin does not pin a peer from a slug alone.'
    fi
    if [[ ${#review_args[@]} -gt 0 ]]; then
      git rev-parse --git-dir >/dev/null 2>&1 || fail 'run peer review from inside a git repository.'
      base=${review_args[1]:-}
      [[ -n "$base" && "$base" != -* ]] || fail '--base must name a single commit.'
      git rev-parse --verify --quiet "${base}^{commit}" >/dev/null || fail '--base must name a single commit.'
    fi
    destination=codex
    (( gemini_requested )) && destination=agy
    (( copilot_requested )) && destination=copilot
    "$script_dir/require-peer-egress.sh" "$destination"
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

      # The peer is handed the change itself. Asking a model to "review the
      # uncommitted changes" without the diff leaves it guessing or shelling
      # out for something it is not allowed to read, which is how a review
      # turns into a timeout with no findings.
      git rev-parse --git-dir >/dev/null 2>&1 || fail 'run peer review from inside a git repository.'
      prompt_file=$(mktemp "${TMPDIR:-/tmp}/cowork-review-XXXXXX.txt")
      trap 'rm -f "$prompt_file"' EXIT
      {
        printf '%s\n\n' "$prompt"
        printf 'Everything you need is below. Answer from this text alone: do not run commands, read files, or wait on background work.\n\n'
        if [[ ${#review_args[@]} -gt 0 ]]; then
          [[ -n "${base-}" ]] || fail 'internal error: --base was not validated.'
          printf '## git diff %s\n\n```diff\n' "$base"
          git diff "$base" --
          printf '```\n'
        else
          printf '## git diff HEAD (staged and unstaged)\n\n```diff\n'
          git diff HEAD
          printf '```\n'
        fi
        printf '\n## Untracked files\n'
        untracked=0
        while IFS= read -r -d '' file; do
          untracked=1
          printf '\n### %s\n\n```diff\n' "$file"
          diff_status=0
          git diff --no-index --binary -- /dev/null "$file" || diff_status=$?
          (( diff_status <= 1 )) || fail "could not read untracked file: $file"
          printf '```\n'
        done < <(git ls-files --others --exclude-standard -z)
        if (( !untracked )); then
          printf '\nNone.\n'
        fi
      } >"$prompt_file"

      model=${explicit_model:-auto}
      # Not `exec`: the trap that removes the prompt file has to run.
      status=0
      "$script_dir/invoke-peer-review.sh" "$via" "$model" \
        --family "$family" --effort "$effort" --prompt-file "$prompt_file" || status=$?
      exit "$status"
    fi
    if [[ -n "$runtime" ]]; then
      exec node "$runtime" "$action" "$arguments"
    fi
    [[ "$action" == review ]] || fail 'adversarial review requires codex@openai-codex.'
    if [[ ${#focus[@]} -gt 0 ]]; then
      if [[ ${#review_args[@]} -gt 0 ]]; then
        fail 'focused review with --base requires the official Codex plugin, or pass --gemini/--copilot; drop --base to use the local CLI.'
      fi
      exec codex review "${focus[*]}"
    fi
    [[ ${#review_args[@]} -gt 0 ]] || review_args=(--uncommitted)
    exec codex review "${review_args[@]}"
    ;;
  transfer|status)
    [[ -n "$runtime" ]] || exit 2
    [[ "$action" == status ]] || "$script_dir/require-peer-egress.sh" codex
    exec node "$runtime" "$action" "$arguments"
    ;;
  *) fail "unsupported action: $action" ;;
esac
