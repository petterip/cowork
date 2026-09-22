#!/usr/bin/env bash
set -euo pipefail

# Single entry point for peer review by another model.
#
# Why a script rather than a hand-written CLI call: every guard below was a
# real failure. `agy` defaults to a 5-minute print timeout, so a hand-rolled
# call dies mid-answer; a peer asked to "review the uncommitted changes"
# without the diff in the prompt has no way to read it, narrates progress it
# cannot make, and burns the whole window; and a review that can write to the
# workspace is not a review.

fail() {
  printf 'Cowork peer review failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat >&2 <<'USAGE'
usage: invoke-peer-review.sh <agy|copilot|claude> <model|auto> (<prompt> | --prompt-file <path>)

  model      a user-supplied name/id, or `auto` to use the peer's native default.
  --effort   optional peer-supported level name (also COWORK_EFFORT).

Environment:
  COWORK_MODEL           model name/id used when the model argument is auto
  COWORK_EFFORT          optional peer-supported level name
  COWORK_PRINT_TIMEOUT   agy print-mode ceiling, default 10m
  COWORK_PROMPT_MAX_BYTES  refuse prompts larger than this, default 1000000
  COWORK_ARGV_MAX_BYTES    above this, an oversized prompt goes to the peer on
                           stdin — stream-json for agy, plain text for claude —
                           instead of as an argument; default 120000, just under
                           the kernel's 128 KiB limit for a single argument.
USAGE
  exit 1
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

[[ $# -ge 3 ]] || usage
via=$1
model=$2
shift 2

prompt=''
prompt_file=''
effort=${COWORK_EFFORT-}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file) [[ $# -ge 2 ]] || fail '--prompt-file requires a path.'; prompt_file=$2; shift 2 ;;
    --effort) [[ $# -ge 2 ]] || fail '--effort requires a value.'; effort=$2; shift 2 ;;
    --) shift; prompt=${1-}; shift $(( $# > 0 ? 1 : 0 )) ;;
    *) [[ -z "$prompt" ]] || fail 'pass the prompt once, or use --prompt-file.'; prompt=$1; shift ;;
  esac
done

[[ "$via" == agy || "$via" == copilot || "$via" == claude ]] ||
  fail 'via must be agy, copilot, or claude.'
"$script_dir/require-peer-egress.sh" "$via"
[[ -z "$effort" || "$effort" =~ ^[[:alnum:]][[:alnum:]_.-]*$ ]] ||
  fail 'effort must be a CLI-safe level name.'

if [[ -n "$prompt_file" ]]; then
  [[ -z "$prompt" ]] || fail 'pass either a prompt argument or --prompt-file, not both.'
  [[ -r "$prompt_file" ]] || fail "prompt file is not readable: $prompt_file"
  prompt=$(cat "$prompt_file")
fi
[[ -n "$prompt" ]] || fail 'prompt must not be empty.'

# A silently truncated diff produces a confident review of code that was never
# shown, so an oversized prompt is refused rather than trimmed.
max_bytes=${COWORK_PROMPT_MAX_BYTES:-1000000}
prompt_bytes=$(printf '%s' "$prompt" | wc -c)
if (( prompt_bytes > max_bytes )); then
  fail "prompt is ${prompt_bytes} bytes, over the ${max_bytes} limit; narrow the review scope or raise COWORK_PROMPT_MAX_BYTES deliberately."
fi

if [[ -z "$model" || "$model" == auto ]]; then
  model=${COWORK_MODEL-}
fi

printf 'cowork: peer review via %s using %s' "$via" "${model:-peer default}" >&2
[[ -z "$effort" ]] || printf ' (effort %s)' "$effort" >&2
printf '\n' >&2

if [[ "$via" == claude ]]; then
  command -v claude >/dev/null 2>&1 || fail 'the Claude Code CLI (claude) is required.'
  # Launching a "Claude review" under API-key or cloud-provider credentials would
  # review with a peer the user did not ask for, so the gate fails closed. Its
  # own diagnosis goes to stderr; only the success line is suppressed.
  "$script_dir/../skills/codex-claude-rally/scripts/assert-subscription-auth.sh" >/dev/null ||
    fail 'Claude subscription authentication is required for the claude peer.'
  # The same scratch-directory isolation as agy: the peer answers from the
  # prompt, so the reviewed tree is not in front of it.
  workspace=$(mktemp -d "${TMPDIR:-/tmp}/cowork-peer-XXXXXX")
  trap 'rm -rf "$workspace"' EXIT
  cd "$workspace"

  claude_args=()
  [[ -z "$model" ]] || claude_args+=(--model "$model")
  [[ -z "$effort" ]] || claude_args+=(--effort "$effort")
  argv_max=${COWORK_ARGV_MAX_BYTES:-120000}
  status=0
  if (( prompt_bytes <= argv_max )); then
    answer=$(claude -p "${claude_args[@]}" -- "$prompt" </dev/null 2>"$workspace/claude-stderr.txt") || status=$?
  else
    answer=$(printf '%s' "$prompt" | claude -p "${claude_args[@]}" 2>"$workspace/claude-stderr.txt") || status=$?
  fi
  if (( status != 0 )) || [[ -z "$answer" ]]; then
    cat "$workspace/claude-stderr.txt" >&2 2>/dev/null || true
    fail "claude produced no answer (exit ${status})."
  fi
  printf '%s\n' "$answer"
  exit 0
fi

if [[ "$via" == agy ]]; then
  command -v agy >/dev/null 2>&1 || fail 'the Anti-Gravity CLI (agy) is required for this peer.'
  # Run from a scratch directory so the peer does not start with the repository
  # in front of it. Defence in depth, not a boundary: an absolute path still
  # reaches anywhere the user can write, so the caller still verifies the tree
  # afterwards (see the skill).
  workspace=$(mktemp -d "${TMPDIR:-/tmp}/cowork-peer-XXXXXX")
  trap 'rm -rf "$workspace"' EXIT
  cd "$workspace"

  argv_max=${COWORK_ARGV_MAX_BYTES:-120000}
  agy_args=(-p "$prompt" --print-timeout "${COWORK_PRINT_TIMEOUT:-10m}" --sandbox)
  [[ -z "$model" ]] || agy_args+=(--model "$model")
  [[ -z "$effort" ]] || agy_args+=(--effort "$effort")
  if (( prompt_bytes <= argv_max )); then
    agy "${agy_args[@]}"
    exit $?
  fi

  # Past ~128 KiB the kernel refuses a single argument with E2BIG — a whole
  # review lost to "Argument list too long". The stream-json input format takes
  # the prompt on stdin instead, with no such ceiling.
  command -v jq >/dev/null 2>&1 ||
    fail "prompt is ${prompt_bytes} bytes, which must go to agy on stdin, and jq is required to encode it."
  printf 'cowork: prompt is %s bytes; sending it on stdin as stream-json\n' "$prompt_bytes" >&2
  transcript=$workspace/transcript.ndjson
  printf '%s' "$prompt" >"$workspace/prompt.txt"
  # -c: one JSON object per line, which is what an NDJSON reader is entitled to
  # expect even if this CLI currently tolerates pretty-printed input.
  pipeline_status=0
  stream_args=(--print= --input-format stream-json --output-format stream-json \
    --print-timeout "${COWORK_PRINT_TIMEOUT:-10m}" --sandbox)
  [[ -z "$model" ]] || stream_args+=(--model "$model")
  [[ -z "$effort" ]] || stream_args+=(--effort "$effort")
  jq -nc --rawfile text "$workspace/prompt.txt" \
    '{event:"user",message:{role:"user",content:[{type:"text",text:$text}]}}' |
    agy "${stream_args[@]}" >"$transcript" || pipeline_status=$?

  # Diagnostics before any exit: the workspace holding the transcript is removed
  # by the EXIT trap, so a bare `set -e` abort here would throw away the only
  # record of what went wrong.
  # `|| true` on both: jq exits non-zero on malformed output, and under `set -e`
  # that would abort before a single diagnostic is printed.
  status=$(jq -r 'select(.event == "result") | .result.status // empty' "$transcript" 2>/dev/null | tail -n1) || true
  response=$(jq -r 'select(.event == "result") | .result.response // empty' "$transcript" 2>/dev/null) || true
  if [[ -n "$status" && "$status" != SUCCESS && "$status" != ERROR ]]; then
    printf 'cowork: agy reported an unfamiliar status %s; treating a non-empty response as the answer.\n' \
      "$status" >&2
  fi
  if (( pipeline_status != 0 )) || [[ -z "$status" || "$status" == ERROR || -z "$response" ]]; then
    jq -r 'select(.event == "result") | .result.error // empty' "$transcript" 2>/dev/null >&2 || true
    tail -n 5 "$transcript" >&2 2>/dev/null || true
    fail "agy produced no answer (exit ${pipeline_status}, status ${status:-none})."
  fi
  printf '%s\n' "$response"
  exit 0
fi

command -v copilot >/dev/null 2>&1 || fail 'the GitHub Copilot CLI (copilot) is required.'
# No stdin path is claimed for Copilot here, so refuse a prompt the kernel would
# reject as an argument rather than letting it fail as "Argument list too long".
if (( prompt_bytes > ${COWORK_ARGV_MAX_BYTES:-120000} )); then
  fail "prompt is ${prompt_bytes} bytes, which exceeds what can be passed to copilot as an argument; narrow the scope or use --via agy."
fi
copilot_args=(-p "$prompt" -s --no-ask-user)
[[ -z "$model" ]] || copilot_args+=(--model="$model")
if [[ -n "$effort" ]]; then
  effort_option=$("$script_dir/cowork" setup --json | jq -r '.peers.copilot.reasoningEffortOption // empty')
  [[ -n "$effort_option" ]] || fail 'this Copilot CLI does not report a reasoning-effort option.'
  copilot_args+=("$effort_option=$effort")
fi
copilot_args+=(
  --allow-tool='shell(git status:*)'
  --allow-tool='shell(git diff:*)'
  --allow-tool='shell(git log:*)'
  --allow-tool='shell(git show:*)'
)
exec copilot "${copilot_args[@]}"
