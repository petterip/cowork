#!/usr/bin/env bash
set -euo pipefail

config_file="${CODEX_HOME:-$HOME/.codex}/config.toml"
if [[ "${COWORK_FULL_ACCESS_AUTHORIZED-}" == "1" ]] || { [[ -f "$config_file" ]] && grep -Eq '^approval_policy[[:space:]]*=[[:space:]]*"never"' "$config_file" && grep -Eq '^sandbox_mode[[:space:]]*=[[:space:]]*"danger-full-access"' "$config_file"; }; then
  printf 'full\n'
else
  printf 'restricted\n'
fi
