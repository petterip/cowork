#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Cowork peer review failed: %s\n' "$1" >&2
  exit 1
}

[[ $# -ge 3 ]] || fail 'usage: invoke-peer-review.sh <agy|copilot> <model> <prompt>'
via=$1
model=$2
prompt=$3

[[ "$via" == agy || "$via" == copilot ]] || fail 'via must be agy or copilot.'
[[ -n "$model" ]] || fail 'model must not be empty.'
[[ -n "$prompt" ]] || fail 'prompt must not be empty.'

if [[ "$via" == agy ]]; then
  command -v agy >/dev/null 2>&1 || fail 'the Antigravity CLI (agy) is required for Gemini.'
  exec agy -p "$prompt" --model "$model" --print-timeout 10m
fi

command -v copilot >/dev/null 2>&1 || fail 'the GitHub Copilot CLI (copilot) is required.'
exec copilot -p "$prompt" -s --no-ask-user --model="$model" \
  --allow-tool='shell(git status:*)' \
  --allow-tool='shell(git diff:*)' \
  --allow-tool='shell(git log:*)' \
  --allow-tool='shell(git show:*)'
