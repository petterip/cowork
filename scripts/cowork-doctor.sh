#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
live=0
json=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --live) live=1; shift ;;
    --json) json=1; shift ;;
    -h|--help)
      printf '%s\n' 'usage: cowork-doctor.sh [--json] [--live]'
      exit 0
      ;;
    *) printf 'Cowork doctor failed: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
if (( live )); then args=(setup --refresh); else args=(doctor); fi
(( json )) && args+=(--json)
exec "$script_dir/cowork" "${args[@]}"
