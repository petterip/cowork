#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
resolver="$repo_root/scripts/resolve-model.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/agy" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == models ]]; then
  printf '%s\n' \
    'gemini-3.7-flash-medium	old' \
    'gemini-4.2-flash-medium	new' \
    'gemini-4.2-flash-high	newh' \
    'gemini-4.2-flash-low	newl' \
    'claude-opus-9-0	other'
  exit 0
fi
printf 'agy:%s\n' "$*" >>"${COWORK_TEST_LOG:-/dev/null}"
EOF
cat >"$fake_bin/copilot" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-} ${2-}" == "help config" ]]; then
  printf '%s\n' \
    '  `model`: AI model to use:' \
    '    - "gemini-3.5-flash"' \
    '    - "gemini-4.1-flash"' \
    '    - "claude-opus-4.6"' \
    '    - "gpt-6-luna"' \
    '    - "gpt-9"' \
    '    - "future-nebula-17"' \
    '' \
    '  `contextTier`: Context tier.'
  exit 0
fi
printf 'copilot:%s\n' "$*" >>"${COWORK_TEST_LOG:-/dev/null}"
EOF
cat >"$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-} ${2-}" == "debug models" ]]; then
  printf '%s\n' '{"models":[{"slug":"gpt-6-astra"},{"slug":"gpt-6-terra"},{"slug":"future-orion-42"}]}'
  exit 0
fi
exit 1
EOF
chmod +x "$fake_bin/agy" "$fake_bin/copilot" "$fake_bin/codex"

tool_path=$(dirname "$(command -v rg)")
export PATH="$fake_bin:$tool_path:/usr/bin:/bin"
[[ "$("$resolver" --family gemini-flash --via agy --effort medium)" == gemini-4.2-flash-medium ]]
[[ "$("$resolver" --family gemini-flash --via agy --effort high)" == gemini-4.2-flash-high ]]
[[ "$("$resolver" --family gemini-flash --via copilot)" == gemini-4.1-flash ]]
[[ "$("$resolver" --family auto --via copilot)" == auto ]]
[[ "$("$resolver" --family named --via copilot --query opus)" == claude-opus-4.6 ]]
[[ "$("$resolver" --family named --via copilot --query luna)" == gpt-6-luna ]]
[[ "$("$resolver" --family named --via copilot --query nebula)" == future-nebula-17 ]]
[[ "$("$resolver" --family named --via codex --query terra)" == gpt-6-terra ]]
[[ "$("$resolver" --family named --via codex --query orion)" == future-orion-42 ]]
[[ "$(COWORK_MODEL=wrong-slug "$resolver" --family named --via copilot --query luna)" == gpt-6-luna ]]
[[ "$(COWORK_MODEL=custom-slug "$resolver" --family gemini-flash --via agy)" == custom-slug ]]

cat >"$fake_bin/agy" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == models ]]; then
  printf '%s\n' 'gemini-4.2-flash	bare' 'claude-opus-9-0	other'
  exit 0
fi
exit 1
EOF
[[ "$("$resolver" --family gemini-flash --via agy --effort medium)" == gemini-4.2-flash ]]

cat >"$fake_bin/agy" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == models ]]; then
  printf '%s\n' 'claude-opus-9-0	other'
  exit 0
fi
exit 1
EOF
if err=$("$resolver" --family gemini-flash --via agy --effort medium 2>&1); then
  printf '%s\n' 'expected resolve-model to fail when agy lists no Flash slug' >&2
  exit 1
fi
printf '%s\n' "$err" | grep -Fq 'listed no Gemini Flash slug'

matches=$(rg -n 'gemini-[0-9]+\.[0-9]+' \
  "$repo_root/scripts" "$repo_root/skills" "$repo_root/README.md" "$repo_root/install.sh" || true)
if [[ -n "$matches" ]]; then
  printf '%s\n' "$matches" >&2
  printf '%s\n' 'Shipped Cowork files still hard-code a Gemini version.' >&2
  exit 1
fi

printf '%s\n' 'Cowork model resolver contract: PASS'
