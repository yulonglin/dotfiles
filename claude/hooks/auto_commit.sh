#!/usr/bin/env bash
# Hook: enqueue guarded auto-commit worker at SessionEnd.

set -euo pipefail

resolve_script_path() {
  local src="${BASH_SOURCE[0]}"
  while [[ -h "$src" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  printf '%s\n' "$(cd -P "$(dirname "$src")" && pwd)/$(basename "$src")"
}

hash_string() {
  local input="$1"
  if command -v sha1sum >/dev/null 2>&1; then
    printf '%s' "$input" | sha1sum | awk '{print $1}'
    return
  fi
  printf '%s' "$input" | shasum -a 1 | awk '{print $1}'
}

script_file="$(resolve_script_path)"
hook_dir="$(cd "$(dirname "$script_file")" && pwd)"
dot_dir="$(cd "$hook_dir/../.." && pwd)"
CONFIG_PATH="${dot_dir}/config/ai_automation.sh"
if [[ -f "$HOME/.claude/ai_automation.sh" ]]; then
  CONFIG_PATH="$HOME/.claude/ai_automation.sh"
fi
if [[ -f "$CONFIG_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_PATH"
fi

: "${AUTO_AGENT_DISABLED_SENTINEL:=$HOME/.claude/flags/auto-agent-disabled}"
: "${AUTO_AGENT_REPO_DISABLED_DIR:=$HOME/.claude/state/repo-disabled}"
: "${AUTO_COMMIT_USE_ASYNC:=1}"

INPUT="$(cat)"
CWD="$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${CWD:-$(pwd)}}"
[[ -z "$PROJECT_DIR" ]] && exit 0

[[ "${CLAUDE_AUTO_COMMIT:-1}" == "0" ]] && exit 0
[[ "${AUTO_AGENT_INTERNAL:-0}" == "1" ]] && exit 0
[[ -f "$AUTO_AGENT_DISABLED_SENTINEL" ]] && exit 0

REPO_ROOT="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -f "$REPO_ROOT/.no-auto-commit" ]] && exit 0
repo_hash="$(hash_string "$REPO_ROOT")"
repo_disabled_sentinel="${AUTO_AGENT_REPO_DISABLED_DIR}/auto-agent-disabled-${repo_hash}"
[[ -f "$repo_disabled_sentinel" ]] && exit 0

worker="${hook_dir}/auto_commit_worker.sh"
[[ -x "$worker" ]] || exit 0

if [[ "${AUTO_COMMIT_USE_ASYNC:-1}" == "1" ]]; then
  nohup env AUTO_AGENT_INTERNAL=1 CLAUDE_AUTO_COMMIT=0 "$worker" "$REPO_ROOT" >/dev/null 2>&1 &
  exit 0
fi

env AUTO_AGENT_INTERNAL=1 CLAUDE_AUTO_COMMIT=0 "$worker" "$REPO_ROOT"
