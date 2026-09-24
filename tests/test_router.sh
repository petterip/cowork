#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
router="$repo_root/scripts/cowork-route.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/bin"
official="$tmp/official"
log="$tmp/calls.log"
export XDG_STATE_HOME="$tmp/state"
mkdir -p "$fake_bin" "$official/scripts"
ln -s "$(command -v jq)" "$fake_bin/jq"
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
  printf '%s\n' 'peer-gamma-3 available'
  exit 0
fi
if [[ "${1-}" == --version ]]; then printf '%s\n' 'gravity-peer 1'; exit 0; fi
if [[ "${1-}" == --help ]]; then printf '%s\n' '  --effort <level>'; exit 0; fi
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
if [[ "${1-} ${2-}" == "help config" ]]; then
  printf '%s\n' \
    '  `model`: AI model to use:' \
    '    - "peer-alpha-2"' \
    '    - "claude-opus-5"' \
    '    - "peer-delta-7"' \
    '    - "future-nebula-17"' \
    '' \
    '  `contextTier`: Context tier.'
  exit 0
fi
if [[ "${1-}" == --version ]]; then printf '%s\n' 'copilot-peer 1'; exit 0; fi
if [[ "${1-}" == --help ]]; then printf '%s\n' '  --reasoning-effort <level>'; exit 0; fi
printf 'copilot:%s\n' "$*" >>"$COWORK_TEST_LOG"
EOF
cat >"$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
if [[ "${1-} ${2-}" == "debug models" ]]; then
  printf '%s\n' '{"models":[{"slug":"peer-beta-7"},{"slug":"future-orion-42"}]}'
  exit 0
fi
if [[ "${1-}" == --version ]]; then printf '%s\n' 'codex-peer 1'; exit 0; fi
printf 'codex:%s\n' "$*" >>"$COWORK_TEST_LOG"
printf 'codex-argc:%s\n' "$#" >>"$COWORK_TEST_LOG"
EOF
chmod +x "$fake_bin/node" "$fake_bin/codex" "$fake_bin/agy" "$fake_bin/copilot"

peer_repo="$tmp/repo"
git init -q "$peer_repo"
git -C "$peer_repo" config user.email test@example.invalid
git -C "$peer_repo" config user.name test
printf '%s\n' base >"$peer_repo/file.txt"
git -C "$peer_repo" add file.txt
git -C "$peer_repo" commit -qm base
printf '%s\n' changed >"$peer_repo/file.txt"
printf '%s\n' 'untracked-review-sentinel' >"$peer_repo/new.txt"
printf '%s\n' '*.deck diff=explode' >"$peer_repo/.gitattributes"
printf '%s\n' 'binary-deck' >"$peer_repo/slides.deck"
git -C "$peer_repo" add .gitattributes slides.deck
git -C "$peer_repo" commit -qm deck
git -C "$peer_repo" config diff.explode.textconv "printf 'expanded-textconv-sentinel'"

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
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--peer agy focus')
grep -Fq 'agy:-p' "$log"
if grep -Fq -- '--model' "$log"; then
  printf '%s\n' 'default peer review unexpectedly pinned a model' >&2
  exit 1
fi
grep -Fq 'untracked-review-sentinel' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" adversarial-review '--peer agy')
grep -Fq 'agy:-p' "$log"
grep -Fq -- '--effort high' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--peer copilot')
grep -Fq 'copilot:-p' "$log"
if grep -Fq -- '--model=' "$log" || grep -Fq -- '--reasoning-effort=' "$log"; then
  printf '%s\n' 'default Copilot review unexpectedly pinned model or effort' >&2
  exit 1
fi

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review \
  '--copilot --model-name=alpha --effort=high')
grep -Fq 'copilot:-p' "$log"
grep -Fq -- '--model=peer-alpha-2' "$log"
grep -Fq -- '--reasoning-effort=high' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review \
  '--copilot --model-name "alpha 2" --effort=high --base HEAD^')
grep -Fq -- '--model=peer-alpha-2' "$log"
grep -Fq -- '--reasoning-effort=high' "$log"
if grep -Fq 'untracked-review-sentinel' "$log"; then
  printf '%s\n' 'committed-range review unexpectedly included untracked files' >&2
  exit 1
fi
if grep -Fq 'expanded-textconv-sentinel' "$log"; then
  printf '%s\n' 'committed-range review unexpectedly expanded a textconv artifact' >&2
  exit 1
fi

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review \
  '--copilot --model-name=delta --effort=high')
grep -Fq -- '--model=peer-delta-7' "$log"
grep -Fq -- '--reasoning-effort=high' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review \
  '--copilot --model-name=nebula --effort=max')
grep -Fq -- '--model=future-nebula-17' "$log"
grep -Fq -- '--reasoning-effort=max' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_MODEL=wrong-slug COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review \
  '--copilot --model-name=nebula --effort=max')
grep -Fq -- '--model=future-nebula-17' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review \
  '--codex --model-name=beta --effort=low')
grep -Fq 'codex:-m peer-beta-7 -c model_reasoning_effort=low review --uncommitted' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review \
  '--codex --model-name=orion --effort=xhigh')
grep -Fq 'codex:-m future-orion-42 -c model_reasoning_effort=xhigh review --uncommitted' "$log"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--codex')
grep -Fq 'codex:review --uncommitted' "$log"

: >"$log"
if PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review \
  '--copilot --model-name=nebula --effort=../../unsafe' 2>"$tmp/route.err"; then
  printf '%s\n' 'expected unsafe effort token to fail' >&2
  exit 1
fi
grep -Fq 'CLI-safe level name' "$tmp/route.err"

: >"$log"
if PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review \
  '--peer agy --copilot' 2>"$tmp/route.err"; then
  printf '%s\n' 'expected conflicting peer flags to fail' >&2
  exit 1
fi
grep -Fq -- '--peer cannot be combined' "$tmp/route.err"

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$official" "$router" review '--peer agy --model=custom-choice')
grep -Fq 'agy:-p' "$log"
grep -Fq 'custom-choice' "$log"

for option in --model --model-name; do
  : >"$log"
  (cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
    "$router" review "--peer copilot $option opus-5.5")
  grep -Fq -- '--model=opus-5.5' "$log"
done

for peer in '--peer agy' '--peer copilot'; do
  : >"$log"
  (cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
    COWORK_MODEL=stale-default COWORK_CODEX_PLUGIN_ROOT="$official" \
    "$router" review "$peer --model chosen-model")
  grep -Fq 'chosen-model' "$log"
  if grep -Fq 'stale-default' "$log"; then
    printf '%s\n' 'Environment default overrode the requested model.' >&2
    exit 1
  fi
  : >"$log"
  (cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
    COWORK_MODEL=configured-model COWORK_CODEX_PLUGIN_ROOT="$official" \
    "$router" review "$peer")
  grep -Fq 'configured-model' "$log"
done

: >"$log"
(cd "$peer_repo" && PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_ARGV_MAX_BYTES=1 COWORK_CODEX_PLUGIN_ROOT="$official" \
  "$router" review '--peer agy') | grep -Fq 'agy review'

: >"$log"
if PATH="$fake_bin:/usr/bin:/bin" COWORK_TEST_LOG="$log" \
  COWORK_CODEX_PLUGIN_ROOT="$tmp/missing" "$router" review '--model custom-choice' 2>"$tmp/route.err"; then
  printf '%s\n' 'expected --model without a peer to fail' >&2
  exit 1
fi
grep -Fq -- 'pass --peer' "$tmp/route.err"

printf '%s\n' 'Cowork router contract: PASS'
