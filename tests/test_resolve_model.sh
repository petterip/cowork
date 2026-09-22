#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
resolver="$repo_root/scripts/resolve-model.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/copilot" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == --version ]]; then printf '%s\n' 'peer-cli 1'; exit 0; fi
if [[ "${1-} ${2-}" == "help config" ]]; then
  printf '%s\n' '  `model`: available:' '    - "peer-alpha-2"' '' '  `other`: value'
  exit 0
fi
if [[ "${1-}" == --help ]]; then printf '%s\n' '  --reasoning-effort <level>'; exit 0; fi
exit 0
EOF
cat >"$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == --version ]]; then printf '%s\n' 'dialog-peer 1'; exit 0; fi
if [[ "${1-} ${2-}" == "auth status" ]]; then printf '%s\n' '{"loggedIn":true}'; exit 0; fi
if [[ "${1-}" == --help ]]; then printf '%s\n' '  --effort <level>'; exit 0; fi
exit 0
EOF
chmod +x "$fake_bin/copilot" "$fake_bin/claude"

tool_path=$(dirname "$(command -v jq)")
export PATH="$fake_bin:$tool_path:/usr/bin:/bin"
export XDG_STATE_HOME="$tmp/state"
[[ "$("$resolver" --via copilot --query 'Alpha 2')" == peer-alpha-2 ]]
[[ "$("$resolver" --via claude --query user-choice)" == user-choice ]]
[[ -z "$("$resolver" --via copilot)" ]]

if err=$("$resolver" --via copilot --query missing 2>&1); then
  printf '%s\n' 'expected an unavailable model to fail' >&2
  exit 1
fi
printf '%s\n' "$err" | grep -Fq 'no model matching'

printf '%s\n' 'Cowork model resolver contract: PASS'
