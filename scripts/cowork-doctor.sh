#!/usr/bin/env bash
set -euo pipefail

# One readiness report for Cowork: which peers exist, whether the installed
# skills still resolve, whether the artifact root is writable, and — on request
# — which model `auto` would pick right now. Replaces remembering which of five
# scripts to run when a delegation fails.

fail() {
  printf 'Cowork doctor failed: %s\n' "$1" >&2
  exit 2
}

usage() {
  cat <<'USAGE'
usage: cowork-doctor.sh [--json] [--live]

  --json  machine-readable report with a `ready` flag and one entry per check
  --live  also run the subscription gate and resolve each installed peer's
          current model; requires account access and is slower
USAGE
}

json_mode=0
live=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)
      json_mode=1
      shift
      ;;
    --live)
      live=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1 (see --help)"
      ;;
  esac
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
rally_scripts="$repo_root/skills/codex-claude-rally/scripts"

check_names=()
check_states=()
check_details=()
required_failed=0

record() {
  check_names+=("$1")
  check_states+=("$2")
  check_details+=("${3-}")
}

bounded() {
  local seconds=$1
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$@"
  else
    "$@"
  fi
}

record_tool() {
  local tool=$1
  local requirement=$2
  local version
  if ! command -v "$tool" >/dev/null 2>&1; then
    if [[ "$requirement" == required ]]; then
      record "$tool" absent 'required before any delegation'
      required_failed=1
    else
      record "$tool" absent 'optional peer'
    fi
    return 0
  fi
  version=$(bounded 5 "$tool" --version 2>/dev/null | head -n1) || version=''
  record "$tool" ok "${version:-present}"
}

json_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  printf '%s' "$value"
}

for tool in claude codex jq git rg; do
  record_tool "$tool" required
done
for tool in agy copilot; do
  record_tool "$tool" optional
done

# The installer already owns the link-state rules, so the doctor asks it rather
# than keeping a second copy of that predicate.
links_output=''
links_status=0
links_output=$("$repo_root/install.sh" --check --agent all 2>&1) || links_status=$?
if (( links_status == 0 )); then
  record 'skill links' ok 'every expected link resolves into this checkout'
else
  problems=$(printf '%s\n' "$links_output" | grep -cE '^(Stale|Missing|Foreign|Absent):' || true)
  record 'skill links' fail "${problems} problem(s); run install.sh --repair --agent all"
  required_failed=1
fi

artifact_root="${XDG_STATE_HOME:-$HOME/.local/state}/cowork/jobs"
probe=''
if mkdir -p "$artifact_root" && probe=$(mktemp "$artifact_root/.probe.XXXXXX") && rm -f "$probe"; then
  record 'state root' ok "$artifact_root"
else
  record 'state root' fail "$artifact_root is not writable"
  required_failed=1
fi

version=''
if command -v jq >/dev/null 2>&1; then
  version=$(jq -r '.version // empty' "$repo_root/plugin.json" 2>/dev/null) || version=''
fi
if [[ -n "$version" ]]; then
  record 'plugin version' ok "$version"
else
  record 'plugin version' fail 'plugin.json has no readable version'
  required_failed=1
fi

access=$("$rally_scripts/detect-full-access.sh" 2>/dev/null) || access=restricted
record 'full access' ok "$access"

if (( live )); then
  if "$rally_scripts/assert-subscription-auth.sh" >/dev/null 2>&1; then
    record 'subscription auth' ok 'first-party subscription'
  else
    record 'subscription auth' fail 'run cowork-setup for the gate diagnosis'
    required_failed=1
  fi
  if command -v claude >/dev/null 2>&1; then
    if slug=$(bounded 30 "$script_dir/resolve-model.sh" --family auto --via claude 2>/dev/null); then
      record 'claude model' ok "$slug"
    else
      record 'claude model' fail 'could not resolve the Claude alias'
      required_failed=1
    fi
  fi
  if command -v agy >/dev/null 2>&1; then
    if slug=$(bounded 30 "$script_dir/resolve-model.sh" --family gemini-flash --via agy --effort medium 2>/dev/null); then
      record 'gemini model' ok "$slug"
    else
      record 'gemini model' fail 'could not resolve a Gemini Flash slug'
    fi
  fi
fi

if (( json_mode )); then
  ready=true
  if (( required_failed )); then
    ready=false
  fi
  printf '{\n  "ready": %s,\n  "checks": [\n' "$ready"
  last=$(( ${#check_names[@]} - 1 ))
  for index in "${!check_names[@]}"; do
    separator=','
    if (( index == last )); then
      separator=''
    fi
    printf '    {"name": "%s", "state": "%s", "detail": "%s"}%s\n' \
      "$(json_escape "${check_names[$index]}")" \
      "$(json_escape "${check_states[$index]}")" \
      "$(json_escape "${check_details[$index]}")" \
      "$separator"
  done
  printf '  ]\n}\n'
  exit "$required_failed"
fi

for index in "${!check_names[@]}"; do
  printf '%-16s %-7s %s\n' "${check_names[$index]}" "${check_states[$index]}" "${check_details[$index]}"
done
if (( links_status != 0 )); then
  printf '\n%s\n' "$links_output"
fi
if (( required_failed )); then
  printf '%s\n' 'Cowork doctor: NEEDS ATTENTION'
  exit 1
fi
printf '%s\n' 'Cowork doctor: ready'
