#!/usr/bin/env bash
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

run_with_timeout() {
  local duration="$1"
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "$duration" "$@"
    return
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$duration" "$@"
    return
  fi

  echo "auto_commit_worker: no timeout utility found; running without timeout" >&2
  "$@"
}

REPO_ROOT="${1:-}"
[[ -z "$REPO_ROOT" ]] && exit 0

script_file="$(resolve_script_path)"
hook_dir="$(cd "$(dirname "$script_file")" && pwd)"
dot_dir="$(cd "$hook_dir/../.." && pwd)"
bin_dir="${dot_dir}/custom_bins"
CONFIG_PATH="${dot_dir}/config/ai_automation.sh"
if [[ -f "$HOME/.claude/ai_automation.sh" ]]; then
  CONFIG_PATH="$HOME/.claude/ai_automation.sh"
fi
if [[ -f "$CONFIG_PATH" ]]; then
  # shellcheck disable=SC1090
  source "$CONFIG_PATH"
fi

: "${AUTO_AGENT_MAX_DEPTH:=2}"
: "${AUTO_AGENT_COOLDOWN_SEC:=120}"
: "${AUTO_AGENT_MAX_PER_HOUR:=20}"
: "${AUTO_AGENT_ANOMALY_ENABLED:=1}"
: "${AUTO_AGENT_DISABLED_SENTINEL:=$HOME/.claude/flags/auto-agent-disabled}"
: "${AUTO_AGENT_REPO_DISABLED_DIR:=$HOME/.claude/state/repo-disabled}"
: "${AUTO_AGENT_APPROVAL_FILE:=$HOME/.claude/flags/auto-agent-approved-until}"
: "${AUTO_AGENT_STATE_DIR:=$HOME/.claude/state}"
: "${AUTO_AGENT_LOG_DIR:=$HOME/.claude/logs/auto-commit}"
: "${AUTO_COMMIT_BACKEND_ORDER:=codex,gemini}"
: "${AUTO_COMMIT_ENABLE_CLAUDE_FALLBACK:=0}"
: "${AUTO_COMMIT_DRY_RUN:=0}"
: "${AUTO_AGENT_EXCLUDE_REGEX:=^\\.claude/worktrees/}"

mkdir -p \
  "$AUTO_AGENT_STATE_DIR" \
  "$AUTO_AGENT_LOG_DIR" \
  "$AUTO_AGENT_REPO_DISABLED_DIR" \
  "$(dirname "$AUTO_AGENT_DISABLED_SENTINEL")"

depth="${AUTO_AGENT_DEPTH:-0}"
if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
  depth=0
fi
if (( depth >= AUTO_AGENT_MAX_DEPTH )); then
  exit 0
fi
export AUTO_AGENT_DEPTH=$((depth + 1))
export AUTO_AGENT_INTERNAL=1
export CLAUDE_AUTO_COMMIT=0

if [[ -f "$AUTO_AGENT_DISABLED_SENTINEL" ]]; then
  exit 0
fi

if [[ -f "$REPO_ROOT/.no-auto-commit" ]]; then
  exit 0
fi

if ! git -C "$REPO_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  exit 0
fi

repo_hash="$(hash_string "$REPO_ROOT")"
repo_disabled_sentinel="${AUTO_AGENT_REPO_DISABLED_DIR}/auto-agent-disabled-${repo_hash}"
if [[ -f "$repo_disabled_sentinel" ]]; then
  exit 0
fi
lock_file="${AUTO_AGENT_STATE_DIR}/auto-commit-${repo_hash}.lock"
stamp_file="${AUTO_AGENT_STATE_DIR}/auto-commit-${repo_hash}.last"
hour_file="${AUTO_AGENT_STATE_DIR}/auto-commit-${repo_hash}.hour"

exec 9>"$lock_file"
if ! flock -n 9; then
  exit 0
fi

now="$(date +%s)"

if [[ -f "$stamp_file" ]]; then
  last_ts="$(cat "$stamp_file" 2>/dev/null || echo 0)"
  if [[ "$last_ts" =~ ^[0-9]+$ ]] && (( now - last_ts < AUTO_AGENT_COOLDOWN_SEC )); then
    exit 0
  fi
fi

# Hourly cap
tmp_hour="$(mktemp)"
if [[ -f "$hour_file" ]]; then
  while IFS= read -r ts; do
    [[ "$ts" =~ ^[0-9]+$ ]] || continue
    if (( now - ts < 3600 )); then
      echo "$ts" >> "$tmp_hour"
    fi
  done < "$hour_file"
fi
current_hour_count="$(wc -l < "$tmp_hour" | tr -d ' ')"
if (( current_hour_count >= AUTO_AGENT_MAX_PER_HOUR )); then
  mv "$tmp_hour" "$hour_file"
  exit 0
fi

# Guard/anomaly checks
if [[ "${AUTO_AGENT_ANOMALY_ENABLED:-1}" == "1" ]]; then
  set +e
  guard_msg="$("${bin_dir}/ccusage-guard" --project "$REPO_ROOT" --enforce --json 2>&1)"
  guard_rc=$?
  set -e
  if (( guard_rc == 20 )); then
    "${bin_dir}/auto-agent-trace" "$REPO_ROOT" >/dev/null 2>&1 || true
    echo "auto-commit blocked (STOP): $guard_msg" >&2
    exit 0
  fi
  if (( guard_rc == 10 )); then
    approval_ok=0
    if [[ -f "$AUTO_AGENT_APPROVAL_FILE" ]]; then
      exp="$(cat "$AUTO_AGENT_APPROVAL_FILE" 2>/dev/null || echo 0)"
      if [[ "$exp" =~ ^[0-9]+$ ]] && (( exp > now )); then
        approval_ok=1
      fi
    fi
    if (( approval_ok == 0 )); then
      "${bin_dir}/auto-agent-trace" "$REPO_ROOT" >/dev/null 2>&1 || true
      echo "auto-commit blocked (WARN needs approval): $guard_msg" >&2
      exit 0
    fi
  fi
fi

if ! git -C "$REPO_ROOT" symbolic-ref HEAD >/dev/null 2>&1; then
  exit 0
fi

git_dir="$(git -C "$REPO_ROOT" rev-parse --git-dir)"
for sentinel in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply BISECT_LOG; do
  if [[ -e "$git_dir/$sentinel" ]]; then
    exit 0
  fi
done

if [[ -n "$(git -C "$REPO_ROOT" diff --name-only --diff-filter=U 2>/dev/null || true)" ]]; then
  exit 0
fi

status_porcelain="$(git -C "$REPO_ROOT" status --porcelain=v1 --untracked-files=all 2>/dev/null || true)"
committable=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  path="${line:3}"
  path="${path##* -> }"
  [[ -z "$path" ]] && continue
  if [[ "$path" =~ $AUTO_AGENT_EXCLUDE_REGEX ]]; then
    continue
  fi
  mode="$(git -C "$REPO_ROOT" ls-files -s -- "$path" 2>/dev/null | awk '{print $1}' | head -1 || true)"
  if [[ "$mode" == "160000" ]]; then
    continue
  fi
  committable=1
  break
done <<< "$status_porcelain"

if (( committable == 0 )); then
  exit 0
fi

echo "$now" > "$stamp_file"
echo "$now" >> "$tmp_hour"
mv "$tmp_hour" "$hour_file"

log_file="${AUTO_AGENT_LOG_DIR}/auto-commit-${repo_hash}-${now}.log"
touch "$log_file"

git_status="$(git -C "$REPO_ROOT" status --short 2>/dev/null || true)"
git_diff_stat="$(git -C "$REPO_ROOT" diff --stat HEAD 2>/dev/null | head -100)"
git_branch="$(git -C "$REPO_ROOT" branch --show-current 2>/dev/null || true)"
git_log="$(git -C "$REPO_ROOT" log --oneline -10 2>/dev/null || true)"

prompt="Follow the /commit workflow strictly and keep output minimal.

1) First inspect:
- GIT_EDITOR=true git status --short --branch
- GIT_EDITOR=true git diff --stat
- GIT_EDITOR=true git log --oneline -3
2) If there is no committable change, exit without committing.
3) If there is a committable change, create one concise commit with a short bullet body.
4) Do not modify or stage gitlinks/submodules (mode 160000) or any path under .claude/worktrees/.

Context:
- Branch: ${git_branch}
- Status:
${git_status}
- Diff stat:
${git_diff_stat}
- Recent commits:
${git_log}

Working directory: ${REPO_ROOT}
Do only git inspection/stage/commit operations."

run_backend() {
  local backend="$1"
  if [[ "$AUTO_COMMIT_DRY_RUN" == "1" ]]; then
    echo "DRY RUN: would invoke backend=${backend}" >> "$log_file"
    return 0
  fi

  case "$backend" in
    codex)
      command -v codex >/dev/null 2>&1 || return 1
      run_with_timeout 240 codex -a never -s workspace-write exec --cd "$REPO_ROOT" --skip-git-repo-check "$prompt" >> "$log_file" 2>&1
      ;;
    gemini)
      command -v gemini >/dev/null 2>&1 || return 1
      run_with_timeout 240 gemini \
        -p "$prompt" --approval-mode yolo --output-format text >> "$log_file" 2>&1
      ;;
    claude)
      [[ "${AUTO_COMMIT_ENABLE_CLAUDE_FALLBACK:-0}" == "1" ]] || return 1
      command -v claude >/dev/null 2>&1 || return 1
      CLAUDE_AUTO_COMMIT=0 CLAUDE_WATCHDOG_ENABLED=0 AUTO_AGENT_INTERNAL=1 \
      run_with_timeout 240 claude -p "$prompt" \
        --allowedTools "Bash(git add:*),Bash(git status:*),Bash(git diff:*),Bash(git log:*),Bash(git commit:*)" \
        >> "$log_file" 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

IFS=',' read -r -a backends <<< "$AUTO_COMMIT_BACKEND_ORDER"
for backend in "${backends[@]}"; do
  backend="$(echo "$backend" | tr -d '[:space:]')"
  [[ -z "$backend" ]] && continue
  if run_backend "$backend"; then
    exit 0
  fi
done

exit 0
