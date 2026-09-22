#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'Installation failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
usage: ./install.sh [--agent <claude|codex|opencode|copilot|dsh|both|all>] [--check|--repair]

  --agent   which agent installation to write (default: both = claude and codex)
  --check   report every expected link without writing; exit 1 when any link is
            missing, stale, or foreign
  --repair  like a normal install, but also replace dangling links that point
            at a previous Cowork checkout, such as after the clone was renamed

`agents` is accepted as a synonym for `dsh`.
USAGE
}

mode=install
target=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      [[ $# -ge 2 ]] || fail '--agent requires a target.'
      target=$2
      shift 2
      ;;
    --agent=*)
      target=${1#--agent=}
      shift
      ;;
    --check)
      mode=check
      shift
      ;;
    --repair)
      mode=repair
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
target=${target:-both}
if [[ "$target" == agents ]]; then
  target=dsh
fi
case "$target" in
  claude | codex | opencode | copilot | dsh | both | all) ;;
  *) fail 'agent must be claude, codex, opencode, copilot, dsh, both, or all.' ;;
esac

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cowork_skills=(cowork cowork-plan cowork-build cowork-review cowork-continue cowork-status cowork-setup cowork-agy cowork-copilot)

codex_root() { printf '%s\n' "${CODEX_HOME:-$HOME/.codex}"; }
agents_root() { printf '%s\n' "${DSH_AGENTS_HOME:-$HOME/.agents}"; }
opencode_root() { printf '%s\n' "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"; }
copilot_root() { printf '%s\n' "${COPILOT_SKILLS_DIR:-$HOME/.copilot}"; }

check_failed=0
report_problem() {
  check_failed=1
}

# A dangling link is Cowork-owned only when its raw target names one of our
# skills inside a checkout named like this project: the pre-rename clone
# (`cowork-claude-codex`) or the current one (`cowork`). Anything else is a
# foreign link and is never moved automatically.
is_owned_stale_skill_link() {
  local destination=$1 name=$2 target
  [[ -L "$destination" && ! -e "$destination" ]] || return 1
  target=$(readlink "$destination")
  [[ "$target" == */skills/"$name" ]] || return 1
  target=$(basename "$(dirname "$(dirname "$target")")")
  [[ "$target" == cowork || "$target" == cowork-claude-codex ]]
}

is_owned_stale_support_link() {
  local destination=$1 target
  [[ -L "$destination" && ! -e "$destination" ]] || return 1
  target=$(basename "$(readlink "$destination")")
  [[ "$target" == cowork || "$target" == cowork-claude-codex ]]
}

install_skill() {
  local source=$1
  local destination_root=$2
  local name
  local destination
  local current

  name=$(basename "$source")
  destination="$destination_root/$name"
  if [[ "$mode" != check ]]; then
    mkdir -p "$destination_root"
  fi

  if [[ -e "$destination" || -L "$destination" ]]; then
    current=$(readlink -f "$destination" 2>/dev/null || true)
    if [[ "$current" == "$source" ]]; then
      if [[ "$mode" == check ]]; then
        printf 'OK: %s\n' "$destination"
      fi
      return 0
    fi
    if is_owned_stale_skill_link "$destination" "$name"; then
      if [[ "$mode" == check ]]; then
        printf 'Stale: %s → %s\n' "$destination" "$(readlink "$destination")"
        report_problem
        return 0
      fi
      if [[ "$mode" == repair ]]; then
        rm "$destination"
        ln -s "$source" "$destination"
        printf 'Repaired stale link: %s → %s\n' "$destination" "$source"
        return 0
      fi
      fail "$destination is a stale Cowork link from a previous checkout; run: ./install.sh --repair --agent <target>"
    fi
    if [[ "$mode" == check ]]; then
      printf 'Foreign: %s\n' "$destination"
      report_problem
      return 0
    fi
    fail "$destination already exists and is not this Cowork checkout; move it aside manually."
  fi

  if [[ "$mode" == check ]]; then
    printf 'Missing: %s\n' "$destination"
    report_problem
    return 0
  fi
  ln -s "$source" "$destination"
  printf 'Linked: %s → %s\n' "$destination" "$source"
}

# Superseded skills are removed from every root this installer owns, including a
# link that dangles at the pre-rename clone. A link that points anywhere else
# belongs to someone else and is left alone.
remove_owned_skill_link() {
  local root=$1
  local name=$2
  local destination
  local current
  destination="$root/skills/$name"
  [[ -L "$destination" ]] || return 0
  current=$(readlink -f "$destination" 2>/dev/null || true)
  if [[ "$current" != "$repo_root/skills/$name" ]] && ! is_owned_stale_skill_link "$destination" "$name"; then
    return 0
  fi
  rm "$destination"
  printf 'Removed superseded Cowork skill link: %s\n' "$destination"
}

remove_legacy_claude_skill() {
  local name=$1
  local destination="$HOME/.claude/skills/$name"
  [[ -L "$destination" ]] || return 0
  [[ "$(readlink -f "$destination")" == "$repo_root/skills/$name" ]] || return 0
  rm "$destination"
  printf 'Removed legacy Claude skill link: %s\n' "$destination"
}

remove_superseded_skills() {
  local root=$1
  local name
  for name in codex-claude-rally claude-handoff cowork-gemini; do
    remove_owned_skill_link "$root" "$name"
  done
}

ensure_support_root() {
  local support_root
  local current
  support_root="$(codex_root)/cowork"
  if [[ "$mode" != check ]]; then
    mkdir -p "$(codex_root)"
  fi

  if [[ -e "$support_root" || -L "$support_root" ]]; then
    current=$(readlink -f "$support_root" 2>/dev/null || true)
    if [[ "$current" == "$repo_root" ]]; then
      if [[ "$mode" == check ]]; then
        printf 'OK: %s\n' "$support_root"
      fi
      return 0
    fi
    if is_owned_stale_support_link "$support_root"; then
      if [[ "$mode" == check ]]; then
        printf 'Stale: %s → %s\n' "$support_root" "$(readlink "$support_root")"
        report_problem
        return 0
      fi
      if [[ "$mode" == repair ]]; then
        rm "$support_root"
        ln -s "$repo_root" "$support_root"
        printf 'Repaired Cowork support link: %s → %s\n' "$support_root" "$repo_root"
        return 0
      fi
      fail "$support_root is a stale Cowork support link; run: ./install.sh --repair --agent <target>"
    fi
    if [[ "$mode" == check ]]; then
      printf 'Foreign: %s\n' "$support_root"
      report_problem
      return 0
    fi
    fail "$support_root already exists and is not this Cowork repository."
  fi

  if [[ "$mode" == check ]]; then
    printf 'Missing: %s\n' "$support_root"
    report_problem
    return 0
  fi
  ln -s "$repo_root" "$support_root"
  printf 'Linked Cowork support files: %s → %s\n' "$support_root" "$repo_root"
}

install_claude_plugin() {
  command -v claude >/dev/null 2>&1 || fail 'Claude Code CLI is required to install the Cowork plugin.'
  claude plugin marketplace add "$repo_root"
  if claude plugin list 2>/dev/null | grep -Fq 'cowork@cowork-claude-codex'; then
    claude plugin uninstall cowork@cowork-claude-codex || true
  fi
  if claude plugin list 2>/dev/null | grep -Fq 'cowork@cowork'; then
    claude plugin update cowork@cowork
  else
    claude plugin install cowork@cowork
  fi
  for name in grill-me-codex grill-with-docs-codex codex-review codex-build; do
    remove_legacy_claude_skill "$name"
  done
  printf '%s\n' 'Restart Claude Code to use the updated /cowork:* commands.'
}

check_claude_plugin() {
  local plugins
  if ! command -v claude >/dev/null 2>&1; then
    printf 'Absent: Claude Code CLI is not on PATH.\n'
    report_problem
    return 0
  fi
  plugins=$(claude plugin list 2>/dev/null || true)
  if grep -Fq 'cowork@cowork-claude-codex' <<<"$plugins"; then
    printf 'Stale: Claude Code plugin id cowork@cowork-claude-codex\n'
    report_problem
  elif grep -Fq 'cowork@cowork' <<<"$plugins"; then
    printf 'OK: Claude Code plugin cowork@cowork\n'
  else
    printf 'Missing: Claude Code plugin cowork@cowork\n'
    report_problem
  fi
}

install_skill_set() {
  local destination_root=$1
  local name
  for name in "${cowork_skills[@]}"; do
    install_skill "$repo_root/skills/$name" "$destination_root"
  done
}

ensure_support_root

if [[ "$target" == claude || "$target" == both || "$target" == all ]]; then
  if [[ "$mode" == check ]]; then
    check_claude_plugin
  else
    install_claude_plugin
  fi
fi

if [[ "$target" == codex || "$target" == both || "$target" == all ]]; then
  if [[ "$mode" != check ]]; then
    remove_superseded_skills "$(codex_root)"
  fi
  install_skill_set "$(codex_root)/skills"
fi

if [[ "$target" == opencode || "$target" == all ]]; then
  install_skill_set "$(opencode_root)/skills"
  if [[ "$mode" != check ]]; then
    printf '%s\n' 'Restart opencode to discover the updated Cowork skills.'
  fi
fi

if [[ "$target" == copilot || "$target" == all ]]; then
  install_skill_set "$(copilot_root)/skills"
  if [[ "$mode" != check ]]; then
    printf '%s\n' 'Restart GitHub Copilot CLI to discover the updated Cowork skills.'
  fi
fi

if [[ "$target" == dsh || "$target" == all ]]; then
  if [[ "$mode" != check ]]; then
    remove_superseded_skills "$(agents_root)"
  fi
  install_skill_set "$(agents_root)/skills"
  if [[ "$mode" != check ]]; then
    printf '%s\n' 'Restart the agent harness to discover the updated Cowork skills.'
  fi
fi

if [[ "$mode" == check ]]; then
  if ((check_failed)); then
    printf '%s\n' 'Cowork install check: NEEDS ATTENTION'
    exit 1
  fi
  printf '%s\n' 'Cowork install check: OK'
fi
