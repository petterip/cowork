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
  local status=${1:-1}
  cat >&2 <<'USAGE'
usage: invoke-peer-review.sh <agy|copilot> <model|auto> (<prompt> | --prompt-file <path>)

  model      an exact slug, or `auto` (also the empty string) to resolve the
             latest Gemini Flash for agy / Copilot's own default.
  --effort   low|medium|high, default medium (also COWORK_EFFORT).
  --family   gemini-flash|auto; default gemini-flash for agy, auto for copilot.
             `--family gemini-flash --via copilot` asks Copilot for Gemini.

Environment:
  COWORK_MODEL           exact slug, wins over resolution
  COWORK_EFFORT          low|medium|high, default medium
  COWORK_PRINT_TIMEOUT   print-mode ceiling, default 10m
  COWORK_PROMPT_MAX_BYTES  refuse prompts larger than this, default 1000000
  COWORK_ARGV_MAX_BYTES    above this, the prompt goes to agy on stdin as
                           stream-json instead of as an argument; default
                           120000, just under the kernel's 128 KiB limit for a
                           single argument.
USAGE
  exit "$status"
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

[[ "${1-}" != --help ]] || usage 0
[[ $# -ge 3 ]] || usage
via=$1
model=$2
shift 2

prompt=''
prompt_file=''
effort=${COWORK_EFFORT:-medium}
family=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt-file) [[ $# -ge 2 ]] || fail '--prompt-file requires a path.'; prompt_file=$2; shift 2 ;;
    --effort) [[ $# -ge 2 ]] || fail '--effort requires a value.'; effort=$2; shift 2 ;;
    --family) [[ $# -ge 2 ]] || fail '--family requires a value.'; family=$2; shift 2 ;;
    --) shift; prompt=${1-}; shift $(( $# > 0 ? 1 : 0 )) ;;
    *) [[ -z "$prompt" ]] || fail 'pass the prompt once, or use --prompt-file.'; prompt=$1; shift ;;
  esac
done

[[ "$via" == agy || "$via" == copilot ]] || fail 'via must be agy or copilot.'
[[ "$effort" == low || "$effort" == medium || "$effort" == high ]] || fail 'effort must be low, medium, or high.'
if [[ -z "$family" ]]; then
  if [[ "$via" == agy ]]; then family=gemini-flash; else family=auto; fi
fi
[[ "$family" == gemini-flash || "$family" == auto ]] || fail 'family must be gemini-flash or auto.'
if [[ "$family" == auto && "$via" == agy ]]; then
  fail 'family auto is only valid via copilot.'
fi

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

# Resolution lives here, at the single choke point, so an unspecified model is
# always the latest Flash rather than whatever the caller remembered.
if [[ -n "${COWORK_MODEL-}" ]]; then
  model=$COWORK_MODEL
elif [[ -z "$model" || "$model" == auto ]]; then
  model=$("$script_dir/resolve-model.sh" --family "$family" --via "$via" --effort "$effort")
fi
[[ -n "$model" ]] || fail 'model must not be empty.'

printf 'cowork: peer review via %s using %s (effort %s, timeout %s)\n' \
  "$via" "$model" "$effort" "${COWORK_PRINT_TIMEOUT:-10m}" >&2

if [[ "$via" == agy ]]; then
  command -v agy >/dev/null 2>&1 || fail 'the Antigravity CLI (agy) is required for Gemini.'
  # Run from a scratch directory so the peer does not start with the repository
  # in front of it. Defence in depth, not a boundary: an absolute path still
  # reaches anywhere the user can write, so the caller still verifies the tree
  # afterwards (see the skill).
  workspace=$(mktemp -d "${TMPDIR:-/tmp}/cowork-peer-XXXXXX")
  trap 'rm -rf "$workspace"' EXIT
  cd "$workspace"

  argv_max=${COWORK_ARGV_MAX_BYTES:-120000}
  if (( prompt_bytes <= argv_max )); then
    agy -p "$prompt" \
      --model "$model" \
      --print-timeout "${COWORK_PRINT_TIMEOUT:-10m}" \
      --sandbox
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
  jq -nc --rawfile text "$workspace/prompt.txt" \
    '{event:"user",message:{role:"user",content:[{type:"text",text:$text}]}}' |
    agy --print= \
      --input-format stream-json \
      --output-format stream-json \
      --model "$model" \
      --print-timeout "${COWORK_PRINT_TIMEOUT:-10m}" \
      --sandbox >"$transcript" || pipeline_status=$?

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
exec copilot -p "$prompt" -s --no-ask-user --model="$model" \
  --allow-tool='shell(git status:*)' \
  --allow-tool='shell(git diff:*)' \
  --allow-tool='shell(git log:*)' \
  --allow-tool='shell(git show:*)'
