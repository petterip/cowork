#!/usr/bin/env bash
set -euo pipefail
umask 077

fail() { printf 'Cowork peer work failed: %s\n' "$1" >&2; exit 1; }

canonicalize_new_path() {
  local target=$1 parent leaf suffix=''
  parent=$(dirname "$target")
  leaf=$(basename "$target")
  while [[ ! -d "$parent" ]]; do
    suffix="/$(basename "$parent")$suffix"
    parent=$(dirname "$parent")
  done
  parent=$(cd "$parent" && pwd -P)
  printf '%s%s/%s\n' "$parent" "$suffix" "$leaf"
}
[[ $# -ge 3 ]] || fail 'usage: invoke-peer-work.sh <build|continue> <agy|copilot> <model|auto> --repo <root> --prompt-file <file> --output <new report> [--source-repo <root>] [--session <id>]'
action=$1 via=$2 model=$3
shift 3
repo='' source_repo='' prompt_file='' output='' session='' effort=${COWORK_EFFORT-}
while [[ $# -gt 0 ]]; do
  [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a value."
  case "$1" in
    --repo) repo=$2 ;;
    --source-repo) source_repo=$2 ;;
    --prompt-file) prompt_file=$2 ;;
    --output) output=$2 ;;
    --session) session=$2 ;;
    --effort) effort=$2 ;;
    *) fail "unknown argument: $1" ;;
  esac
  shift 2
done
[[ "$action" == build || "$action" == continue ]] || fail 'action must be build or continue.'
[[ "$via" == agy || "$via" == copilot ]] || fail 'provider must be agy or copilot.'
[[ -z "$effort" || "$effort" =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]] || fail 'invalid effort.'
[[ "$repo" == /* && -d "$repo" ]] || fail '--repo must be an absolute Git root.'
repo=$(cd "$repo" && pwd -P)
[[ "$(git -C "$repo" rev-parse --show-toplevel)" == "$repo" ]] || fail '--repo must be the Git root.'
if [[ "$action" == build ]]; then
  [[ "$source_repo" == /* && -d "$source_repo" ]] || fail 'build requires --source-repo.'
  source_repo=$(cd "$source_repo" && pwd -P)
  [[ "$(git -C "$source_repo" rev-parse --show-toplevel)" == "$source_repo" ]] || fail '--source-repo must be the Git root.'
  [[ "$repo" != "$source_repo" ]] || fail 'build requires an isolated worker worktree.'
  git -C "$source_repo" worktree list --porcelain | grep -Fxq "worktree $repo" || fail 'worker is not registered with the source repository.'
  [[ "$(git -C "$repo" rev-parse HEAD)" == "$(git -C "$source_repo" rev-parse HEAD)" ]] || fail 'worker/source base mismatch; verify the recorded base before launch.'
fi
[[ -r "$prompt_file" && -s "$prompt_file" ]] || fail 'prompt file must be readable and nonempty.'
prompt=$(cat "$prompt_file")
[[ -n "$prompt" ]] || fail 'prompt must not be empty.'
[[ $(printf '%s' "$prompt" | wc -c) -le ${COWORK_ARGV_MAX_BYTES:-120000} ]] || fail 'prompt exceeds argument limit; narrow this phase.'
[[ "$output" == /* ]] || fail '--output must be a new absolute external path.'
output=$(canonicalize_new_path "$output")
for tree in "$repo" "$source_repo"; do
  [[ -z "$tree" ]] && continue
  [[ "$output" != "$tree" && "$output" != "$tree/"* ]] || fail 'report must be outside the working trees.'
done
[[ ! -e "$output" && ! -L "$output" ]] || fail 'report already exists; choose a new round path.'
command -v "$via" >/dev/null 2>&1 || fail "$via CLI is required."
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [[ -z "$model" || "$model" == auto ]]; then
  model=${COWORK_MODEL-}
fi
access=$("$script_dir/../skills/codex-claude-rally/scripts/detect-full-access.sh")
if [[ "$via" == agy ]]; then
  args=(-p "$prompt" --mode accept-edits --print-timeout "${COWORK_PRINT_TIMEOUT:-10m}")
  [[ -z "$model" ]] || args+=(--model "$model")
  [[ -z "$effort" ]] || args+=(--effort "$effort")
  [[ "$access" != full ]] || args+=(--dangerously-skip-permissions)
  [[ -z "$session" ]] || args+=(--conversation "$session")
else
  args=(-p "$prompt" -s --no-ask-user)
  [[ -z "$model" ]] || args+=(--model="$model")
  if [[ -n "$effort" ]]; then
    effort_option=$("$script_dir/cowork" setup --json | jq -r '.peers.copilot.reasoningEffortOption // empty')
    [[ -n "$effort_option" ]] || fail 'this Copilot CLI does not report a reasoning-effort option.'
    args+=("$effort_option=$effort")
  fi
  [[ "$access" != full ]] || args+=(--allow-all)
  [[ -z "$session" ]] || args+=(--resume="$session")
fi
mkdir -p "$(dirname "$output")"
run_dir="$output.run"
mkdir "$run_dir" || fail 'round artifacts already exist; choose a new output path.'
printf '%s\n' "$prompt" >"$run_dir/request.md"
printf 'action=%s\nprovider=%s\nmodel=%s\nrepo=%s\naccess=%s\nsession=%s\n' \
  "$action" "$via" "$model" "$repo" "$access" "$session" >"$run_dir/context.txt"
printf 'cowork: %s via %s using %s in %s; artifacts %s\n' "$action" "$via" "${model:-peer default}" "$repo" "$run_dir" >&2
status=0
( cd "$repo" && "$via" "${args[@]}" < /dev/null ) >"$run_dir/stdout" 2>"$run_dir/stderr" || status=$?
printf '%s\n' "$status" >"$run_dir/exit-code"
(( status == 0 )) || fail "worker exited $status; inspect $run_dir/stderr."
grep -q '[^[:space:]]' "$run_dir/stdout" || fail "worker returned no report; inspect $run_dir."
# An atomic, non-overwriting publication on the same filesystem.
ln "$run_dir/stdout" "$output" || fail 'report publication failed; artifacts retained.'
printf '%s\n' "$output"
