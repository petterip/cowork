#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Cowork model resolution failed: %s\n' "$1" >&2
  exit 1
}

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
via=''
query=''
refresh=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --via) [[ $# -ge 2 ]] || fail '--via requires a peer.'; via=$2; shift 2 ;;
    --query) [[ $# -ge 2 ]] || fail '--query requires a model name or id.'; query=$2; shift 2 ;;
    --refresh) refresh=1; shift ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$via" ]] || fail '--via is required.'
args=(resolve --peer "$via" --json)
[[ -z "$query" ]] || args+=(--model "$query")
(( refresh )) && args+=(--refresh)
result=$("$script_dir/cowork" "${args[@]}")
jq -r '.model // empty' <<<"$result"
