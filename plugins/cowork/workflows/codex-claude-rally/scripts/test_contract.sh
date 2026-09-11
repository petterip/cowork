#!/usr/bin/env bash
set -euo pipefail

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
verifier="$skill_dir/scripts/verify-environment.sh"
rallyctl="$skill_dir/scripts/rallyctl.sh"

fail() {
  printf 'Rally contract test failed: %s\n' "$1" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "expected command to fail: $*"
  fi
}

expect_failure "$skill_dir/scripts/create-rally-job.sh" missing-repo read-only

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fake_bin="$tmp/bin"
fake_home="$tmp/home"
fake_state="$tmp/state"
mkdir -p "$fake_bin" "$fake_home/.claude" "$fake_state"

for script in "$skill_dir"/scripts/*.sh; do bash -n "$script"; done
expect_failure env PATH="/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" "$verifier"

cat > "$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > "$fake_bin/claude" <<'EOF'
#!/usr/bin/env bash
if [[ "$1 $2 $3" == 'auth status --json' ]]; then
  printf '%s\n' '{"loggedIn":true,"authMethod":"claude.ai","apiProvider":"firstParty","subscriptionType":"max"}'
  exit 0
fi
exit 1
EOF
chmod +x "$fake_bin/codex" "$fake_bin/claude"
printf '%s\n' 'approval_policy = "never"' 'sandbox_mode = "danger-full-access"' > "$fake_home/.codex-config"
mkdir -p "$fake_home/.codex"
mv "$fake_home/.codex-config" "$fake_home/.codex/config.toml"

output=$(PATH="$fake_bin:/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" "$verifier")
for check in 'Codex CLI: PASS' 'Claude Code CLI: PASS' 'Subscription authentication: PASS' 'Full-access inheritance: PASS' 'External artifact root: PASS'; do
  grep -Fq "$check" <<<"$output"
done

repo="$tmp/repo"
git init -q "$repo"
git -C "$repo" config user.email test@example.invalid
git -C "$repo" config user.name test
printf '%s\n' base > "$repo/base.txt"
git -C "$repo" add base.txt
git -C "$repo" commit -qm base
expect_failure "$skill_dir/scripts/create-rally-job.sh" missing-proof write --repo "$repo" --allowed-path src

write_request() {
  local request=$1
  printf '%s\n' \
    '# Claude work request' '' '## Task' 'Review the bounded target.' '' \
    '## Mode and allowed paths' 'Read-only or exact declared write scope.' '' \
    '## Source of truth' 'The declared repository files.' '' \
    '## Proof command' 'none' '' '## Non-goals' 'Do not exceed the declared scope.' \
    > "$request"
}

job_dir=$(cd "$tmp" && PATH="$fake_bin:/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" \
  "$skill_dir/scripts/create-rally-job.sh" test-job write --repo "$repo" --allowed-path src --proof-command 'true')
[[ "$(jq -r '.repository_path' "$job_dir/manifest.json")" == "$repo" ]] || fail 'explicit repository path was not recorded.'
grep -Fq 'Mode: write' "$job_dir/requests/001.md" || fail 'request mode was not prefilled.'
grep -Fq -- '- src' "$job_dir/requests/001.md" || fail 'request allowed paths were not prefilled.'
grep -Fxq 'true' "$job_dir/requests/001.md" || fail 'request proof command was not prefilled.'
"$skill_dir/scripts/validate-rally-job.sh" "$job_dir"
expect_failure "$rallyctl" transition "$job_dir" CREATED RUNNING codex
worker="$tmp/worker"
git -C "$repo" worktree add -q --detach "$worker"
"$rallyctl" bind-worker "$job_dir" "$worker"
expect_failure "$rallyctl" transition "$job_dir" CREATED RUNNING codex
write_request "$job_dir/requests/001.md"
"$rallyctl" transition "$job_dir" CREATED RUNNING codex
printf '%s\n' tampered > "$job_dir/requests/001.md"
expect_failure "$skill_dir/scripts/validate-rally-job.sh" "$job_dir"
write_request "$job_dir/requests/001.md"
mkdir -p "$worker/src"
printf '%s\n' ok > "$worker/src/allowed.txt"
"$skill_dir/scripts/validate-rally-job.sh" "$job_dir"
printf '%s\n' no > "$worker/outside.txt"
expect_failure "$skill_dir/scripts/validate-rally-job.sh" "$job_dir"
rm "$worker/outside.txt"
expect_failure "$rallyctl" transition "$job_dir" CREATED VERIFYING codex
printf '%s\n' response > "$job_dir/responses/001.md"
"$rallyctl" transition "$job_dir" RUNNING WAITING_FOR_CODEX claude
printf '%s\n' tampered > "$job_dir/responses/001.md"
expect_failure "$rallyctl" transition "$job_dir" WAITING_FOR_CODEX VERIFYING codex
printf '%s\n' response > "$job_dir/responses/001.md"
"$rallyctl" transition "$job_dir" WAITING_FOR_CODEX VERIFYING codex
printf '%s\n' review > "$job_dir/reviews/001.md"
"$rallyctl" transition "$job_dir" VERIFYING ACCEPTED codex
expect_failure "$rallyctl" transition "$job_dir" ACCEPTED RUNNING codex

readonly_job=$(cd "$tmp" && PATH="$fake_bin:/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" \
  "$skill_dir/scripts/create-rally-job.sh" readonly-job read-only --repo "$repo")
grep -Fq 'Mode: read-only' "$readonly_job/requests/001.md" || fail 'read-only request mode was not prefilled.'
grep -Fq 'Allowed paths: none declared' "$readonly_job/requests/001.md" || fail 'empty allowed paths were not prefilled.'
grep -Fxq 'none' "$readonly_job/requests/001.md" || fail 'default proof command was not prefilled.'
"$skill_dir/scripts/validate-rally-job.sh" "$readonly_job"
expect_failure "$rallyctl" transition "$readonly_job" CREATED RUNNING codex
write_request "$readonly_job/requests/001.md"
"$rallyctl" transition "$readonly_job" CREATED RUNNING codex
"$rallyctl" record-worker "$readonly_job" worker-1 null "$repo"
"$rallyctl" record-worker "$readonly_job" worker-1 session-1 "$repo"
"$rallyctl" record-worker "$readonly_job" worker-1 session-1 "$repo"
[[ "$(jq -r '.claude_worker_id' "$readonly_job/manifest.json")" == worker-1 ]] || fail 'worker ID was not recorded.'
[[ "$(jq -r '.claude_session_id' "$readonly_job/manifest.json")" == session-1 ]] || fail 'worker session ID was not completed.'
expect_failure "$rallyctl" record-worker "$readonly_job" worker-2 session-2 "$repo"

stopped_template_job=$(cd "$tmp" && PATH="$fake_bin:/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" \
  "$skill_dir/scripts/create-rally-job.sh" stopped-template-job read-only --repo "$repo")
"$rallyctl" transition "$stopped_template_job" CREATED STOPPED codex
"$skill_dir/scripts/validate-rally-job.sh" "$stopped_template_job"

followup_job=$(cd "$tmp" && PATH="$fake_bin:/usr/bin:/bin" HOME="$fake_home" XDG_STATE_HOME="$fake_state" \
  "$skill_dir/scripts/create-rally-job.sh" followup-job read-only --repo "$repo")
write_request "$followup_job/requests/001.md"
"$rallyctl" transition "$followup_job" CREATED RUNNING codex
printf '%s\n' response > "$followup_job/responses/001.md"
"$rallyctl" transition "$followup_job" RUNNING WAITING_FOR_CODEX claude
"$rallyctl" transition "$followup_job" WAITING_FOR_CODEX VERIFYING codex
write_request "$followup_job/requests/002.md"
"$rallyctl" transition "$followup_job" VERIFYING RUNNING codex
[[ "$(jq -r '.round' "$followup_job/manifest.json")" == 2 ]] || fail 'follow-up did not increment the round.'
"$skill_dir/scripts/validate-rally-job.sh" "$followup_job"

grep -Fq 'full_access_authorized' "$skill_dir/SKILL.md"
grep -Fq 'WAITING_FOR_HUMAN' "$skill_dir/references/job-protocol.md"
grep -Fq 'STOPPED' "$skill_dir/references/job-protocol.md"
if rg -n 'claude -p "\$\{ACCESS_ARGS' "$skill_dir" -g '!scripts/**' | grep -v '/SKILL.md:'; then
  printf '%s\n' 'Skill contains a claude -p command outside SKILL.md.' >&2
  exit 1
fi
p_count=$(rg -c 'claude -p "\$\{ACCESS_ARGS' "$skill_dir/SKILL.md" || true)
[[ "${p_count:-0}" == 1 ]] || fail 'SKILL.md must contain exactly one claude -p command.'
print_block=$(awk '/claude -p "\$\{ACCESS_ARGS/,/< \/dev\/null/' "$skill_dir/SKILL.md")
printf '%s\n' "$print_block" | grep -Fq '< /dev/null' || fail 'print-mode fallback must close stdin.'
printf '%s\n' "$print_block" | grep -Fq -- '--add-dir "$RALLY_DIR"' \
  || fail 'print-mode fallback must add the job directory.'
printf '%s\n' "$print_block" | grep -Fq -- '--output-format stream-json' \
  || fail 'print-mode fallback must stream; --output-format text is silent until exit.'
if printf '%s\n' "$print_block" | grep -Fq -- '--cwd'; then
  fail 'print mode must not pass --cwd; claude -p rejects it.'
fi
launch_block=$(awk '/^\( cd "\$TARGET_REPO" && claude --bg/ && !seen {inb=1; seen=1} inb {print} /^claude agents /{inb=0}' "$skill_dir/SKILL.md")
[[ -n "$launch_block" ]] || fail 'launch must cd into the recorded repository inside a subshell.'
if rg -q '^cd "\$TARGET_REPO"$' "$skill_dir/SKILL.md"; then
  fail 'a bare cd would strand the shell and break the relative rallyctl paths.'
fi
printf '%s\n' "$print_block" | grep -Fq 'cd "$TARGET_REPO" &&' \
  || fail 'print mode must also run from the recorded repository.'
if rg -q 'HOME/\.codex/skills/codex-claude-rally' "$skill_dir/SKILL.md"; then
  fail 'the installer removes ~/.codex/skills/codex-claude-rally; use a skill-relative script path.'
fi
grep -Fq 'kind == "background"' "$skill_dir/SKILL.md" \
  || fail 'worker lookup must exclude interactive rows, which have no id or state.'
grep -Fq 'not a flag validator' "$skill_dir/SKILL.md" \
  || fail 'SKILL.md must record that claude --bg exits 0 on an unknown option.'
for observed_state in working "done" blocked failed stopped; do
  grep -Fq "\`$observed_state\`" "$skill_dir/SKILL.md" \
    || fail "launch classification is missing the observed background state: $observed_state"
done
if rg -q 'state .running.' "$skill_dir/SKILL.md"; then
  fail 'claude agents never reports a running state; the observed values are working/done/blocked/failed/stopped.'
fi
printf '%s\n' "$launch_block" | grep -Fq -- '--add-dir "$TARGET_REPO"' \
  || fail 'launch must grant access to the reviewed repository.'
printf '%s\n' "$launch_block" | grep -Fq -- 'claude agents --cwd "$TARGET_REPO"' \
  || fail '--cwd must remain on the claude agents listing command.'
if printf '%s\n' "$launch_block" | grep -v '^claude agents ' | grep -Fq -- '--cwd'; then
  fail 'claude --bg must not pass --cwd; the session is created failed.'
fi
printf '%s\n' "$launch_block" | grep -Fq -- '-- "$RALLY_PROMPT"' \
  || fail 'launch must separate the prompt with --; --add-dir is variadic and swallows it.'
printf '%s\n' "$print_block" | grep -Fq -- '-- "$RALLY_PROMPT"' \
  || fail 'print mode must separate the prompt with --.'
grep -Fq 'variadic' "$skill_dir/SKILL.md" \
  || fail 'SKILL.md must explain why the prompt needs the -- separator.'
grep -Fq '`--cwd` is not a launch flag' "$skill_dir/SKILL.md" \
  || fail 'SKILL.md must state that --cwd is agents-only.'
grep -Fq 'job not found' "$skill_dir/SKILL.md" \
  || fail 'launch classification must separate a failed worker from an idle one.'
grep -Fq 'idle — send a prompt to start' "$skill_dir/SKILL.md" \
  || fail 'print-mode fallback missing idle marker.'
grep -Fqi 'never print-fallback a failed worker' "$skill_dir/SKILL.md" \
  || fail 'print mode must be forbidden as a recovery for a failed worker.'
grep -Fq 'session state is `failed`' "$skill_dir/references/job-protocol.md" \
  || fail 'recovery table must cover a failed background worker.'
review_skill="$skill_dir/../cowork-review/SKILL.md"
if [[ -f "$review_skill" ]]; then
  grep -Fq -- '--cloud' "$review_skill" \
    || fail 'peer resolution must forbid a cloud stand-in for the Claude peer.'
  grep -Fq 'subagent mode may stand in' "$review_skill" \
    || fail 'peer resolution must forbid a subagent stand-in for the Claude peer.'
fi
grep -Fq 'transcript-only' "$skill_dir/SKILL.md" \
  || fail 'print-mode fallback must publish stdout when the artifact is missing.'
if rg -n 'REVIEW_PROMPT|/tmp/codex-(build|verdict)' "$skill_dir/../codex-build" "$skill_dir/../codex-review" "$skill_dir/../grill-me-codex" "$skill_dir/../grill-with-docs-codex" >/dev/null; then
  printf '%s\n' 'Claude-to-Codex skill contains an undefined prompt or predictable result path.' >&2
  exit 1
fi

printf '%s\n' 'Rally skill contract: PASS'
