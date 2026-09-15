#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
router="$repo_root/skills/cowork-runtime/scripts/cowork-route.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/bin"
official="$tmp/official"
log="$tmp/calls.log"
peer_review="$repo_root/skills/cowork-runtime/scripts/invoke-peer-review.sh"
mkdir -p "$fake_bin" "$official/scripts"
touch "$official/scripts/codex-companion.mjs"

cat >"$fake_bin/node" <<'EOF'
#!/usr/bin/env bash
printf 'node:%s\n' "$*" >>"$COWORK_TEST_LOG"
EOF
cat >"$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
printf 'codex:%s\n' "$*" >>"$COWORK_TEST_LOG"
printf 'codex-argc:%s\n' "$#" >>"$COWORK_TEST_LOG"
EOF
cat >"$fake_bin/agy" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == models ]]; then
  printf '%s\n' \
    'gemini-3.7-flash-medium	old' \
    'gemini-4.2-flash-medium	new' \
    'gemini-4.2-flash-high	newh'
  exit 0
fi
if [[ " $* " == *" --input-format stream-json "* ]]; then
  input=$(cat)
  [[ -n "$input" ]]
  printf '%s\n' '{"event":"result","result":{"status":"SUCCESS","response":"agy review"}}'
  exit 0
fi
if [[ "${1-}" == -p ]]; then
  printf 'agy-prompt:%s\n' "${2-}" >>"$COWORK_TEST_LOG"
fi
printf 'agy:%s\n' "$*" >>"$COWORK_TEST_LOG"
EOF
cat >"$fake_bin/copilot" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-}" == /model ]]; then
  printf '%s\n' '[{"id":"gemini-3.5-flash"},{"id":"gemini-4.1-flash"}]'
  exit 0
fi
printf 'copilot:%s\n' "$*" >>"$COWORK_TEST_LOG"
EOF
chmod +x "$fake_bin/node" "$fake_bin/codex" "$fake_bin/agy" "$fake_bin/copilot"
[[ -x "$repo_root/skills/cowork-runtime/scripts/require-peer-egress.sh" ]] ||
  { printf '%s\n' 'peer egress gate is not executable' >&2; exit 1; }

export COWORK_DATA_CLASSIFICATION=internal
export COWORK_APPROVED_DESTINATIONS=codex,agy,copilot

peer_repo="$tmp/repo"
git init -q "$peer_repo"
git -C "$peer_repo" config user.email test@example.invalid
git -C "$peer_repo" config user.name test
printf '%s\n' base >"$peer_repo/file.txt"
git -C "$peer_repo" add file.txt
git -C "$peer_repo" commit -qm base
printf '%s\n' changed >"$peer_repo/file.txt"
printf '%s\n' 'untracked-review-sentinel' >"$peer_repo/new.txt"

: >"$log"
if (cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_DATA_CLASSIFICATION= COWORK_APPROVED_DESTINATIONS= \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--copilot') 2>"$tmp/route.err"; then
  printf '%s\n' 'expected an unclassified peer launch to fail' >&2
  exit 1
fi
[[ ! -s "$log" ]]
grep -Fq 'COWORK_DATA_CLASSIFICATION' "$tmp/route.err"

: >"$log"
if PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_DATA_CLASSIFICATION= COWORK_APPROVED_DESTINATIONS= \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" transfer 'handoff' 2>"$tmp/route.err"; then
  printf '%s\n' 'expected an unclassified transfer to fail' >&2
  exit 1
fi
[[ ! -s "$log" ]]
grep -Fq 'COWORK_DATA_CLASSIFICATION' "$tmp/route.err"

: >"$log"
PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_DATA_CLASSIFICATION= COWORK_APPROVED_DESTINATIONS= \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" status
grep -Fq 'node:' "$log"

: >"$log"
if (cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_APPROVED_DESTINATIONS=agy COWORK_CODEX_PLUGIN_ROOT="$official" \
  "$router" review '--copilot') 2>"$tmp/route.err"; then
  printf '%s\n' 'expected a destination-mismatched peer launch to fail' >&2
  exit 1
fi
[[ ! -s "$log" ]]
grep -Fq "destination 'copilot'" "$tmp/route.err"

: >"$log"
if (cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_DATA_CLASSIFICATION=restricted COWORK_REDACTION_CONFIRMED=true \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--gemini') 2>"$tmp/route.err"; then
  printf '%s\n' 'expected a restricted peer launch to fail' >&2
  exit 1
fi
[[ ! -s "$log" ]]
grep -Fq 'not permitted for peer export' "$tmp/route.err"

: >"$log"
if PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_DATA_CLASSIFICATION= COWORK_APPROVED_DESTINATIONS= \
  "$peer_review" agy auto 'review' 2>"$tmp/route.err"; then
  printf '%s\n' 'expected direct peer invocation without classification to fail' >&2
  exit 1
fi
[[ ! -s "$log" ]]
grep -Fq 'COWORK_DATA_CLASSIFICATION' "$tmp/route.err"

: >"$log"
PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_DATA_CLASSIFICATION=internal \
  COWORK_APPROVED_DESTINATIONS=agy "$peer_review" agy auto 'review'
grep -Fq 'agy:' "$log"

: >"$log"
if PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_DATA_CLASSIFICATION=secret COWORK_APPROVED_DESTINATIONS=agy \
  "$peer_review" agy auto 'review' 2>"$tmp/route.err"; then
  printf '%s\n' 'expected an unknown classification to fail' >&2
  exit 1
fi
[[ ! -s "$log" ]]
grep -Fq 'set COWORK_DATA_CLASSIFICATION' "$tmp/route.err"

: >"$log"
if (cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_DATA_CLASSIFICATION= COWORK_APPROVED_DESTINATIONS= \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" adversarial-review '--gemini') \
  2>"$tmp/route.err"; then
  printf '%s\n' 'expected unclassified adversarial review to fail' >&2
  exit 1
fi
[[ ! -s "$log" ]]
grep -Fq 'COWORK_DATA_CLASSIFICATION' "$tmp/route.err"

: >"$log"
if PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_DATA_CLASSIFICATION= COWORK_APPROVED_DESTINATIONS= \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--wait' 2>"$tmp/route.err"; then
  printf '%s\n' 'expected an unclassified default peer launch to fail' >&2
  exit 1
fi
[[ ! -s "$log" ]]
grep -Fq 'COWORK_DATA_CLASSIFICATION' "$tmp/route.err"

PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--wait'
grep -Fq 'node:' "$log"
grep -Fq ' review --wait' "$log"

: >"$log"
PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$tmp/missing" "$router" review 'focus'
grep -Fq 'codex:review focus' "$log"

: >"$log"
if PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$tmp/missing" "$router" review '--base main focus' 2>"$tmp/route.err"; then
  printf '%s\n' 'expected focused --base review without official runtime to fail' >&2
  exit 1
fi
grep -Fq 'drop --base' "$tmp/route.err"

: >"$log"
PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$tmp/missing" "$router" review '--base main'
grep -Fq 'codex:review --base main' "$log"

: >"$log"
PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$tmp/missing" "$router" review
grep -Fq 'codex-argc:2' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--gemini focus')
grep -Fq 'agy:-p' "$log"
grep -Fq 'gemini-4.2-flash-medium' "$log"
grep -Fq 'untracked-review-sentinel' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" adversarial-review '--gemini')
grep -Fq 'agy:-p' "$log"
grep -Fq 'gemini-4.2-flash-high' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--copilot')
grep -Fq 'copilot:-p' "$log"
grep -Fq -- '--model=auto' "$log"

: >"$log"
if (cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review \
  '--gemini --copilot') 2>"$tmp/route.err"; then
  printf '%s\n' 'expected conflicting peer flags to fail' >&2
  exit 1
fi
grep -Fq -- '--gemini cannot be combined with --copilot' "$tmp/route.err"
[[ ! -s "$log" ]]

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--gemini --model=custom-flash')
grep -Fq 'agy:-p' "$log"
grep -Fq 'custom-flash' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_ARGV_MAX_BYTES=1 COWORK_CODEX_PLUGIN_ROOT="$official" \
  "$router" review '--gemini') | grep -Fq 'agy review'

: >"$log"
if PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$tmp/missing" "$router" review '--model custom-flash' 2>"$tmp/route.err"; then
  printf '%s\n' 'expected --model without a peer to fail' >&2
  exit 1
fi
grep -Fq -- '--gemini or --copilot' "$tmp/route.err"

printf '%s\n' 'Cowork router contract: PASS'
