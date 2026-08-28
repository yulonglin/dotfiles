# aliases/claude.sh — Claude Code launcher, worktree helpers, AI CLI tool management

# Helper: activate .venv from current dir or git repo root
# Note: no underscore prefix - Claude Code shell snapshots filter out _-prefixed functions
activate_venv() {
    if [ -f ".venv/bin/activate" ]; then
        # shellcheck disable=SC1091
        source .venv/bin/activate
    elif git rev-parse --is-inside-work-tree &>/dev/null; then
        local repo_root
        repo_root="$(git rev-parse --show-toplevel)"
        if [ -f "$repo_root/.venv/bin/activate" ]; then
            # shellcheck disable=SC1091
            source "$repo_root/.venv/bin/activate"
        fi
    fi
}

_claude_prepare_telegram_state() {
    local state_dir="$1"
    local secret_name="$2"

    if [[ -z "$state_dir" || -z "$secret_name" ]]; then
        echo "claude: TELEGRAM_STATE_DIR and DOTFILES_TELEGRAM_BOT_SECRET must both be set" >&2
        return 1
    fi

    if [[ ! -x "$DOT_DIR/custom_bins/dotfiles-secrets" ]]; then
        echo "claude: $DOT_DIR/custom_bins/dotfiles-secrets not found" >&2
        return 1
    fi

    if ! "$DOT_DIR/custom_bins/dotfiles-secrets" write-telegram-env "$secret_name" "$state_dir" >/dev/null; then
        echo "claude: failed to materialize Telegram token from $secret_name" >&2
        return 1
    fi
}

claude() {
    # Use tmpfs for Claude Code temp files (faster, avoids disk I/O)
    # Only on Linux where /run/user/<uid> exists (systemd tmpfs)
    if [[ "$OSTYPE" == linux* ]] && [[ -d "/run/user/$(id -u)" ]]; then
        export CLAUDE_CODE_TMPDIR="/run/user/$(id -u)"
    fi

    # Parse -t/--task argument for custom task name
    local args=() task_name=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --)
                # Everything after `--` is the caller's, not ours. Without this
                # a seed prompt of exactly `-t` was parsed as OUR task flag; no
                # value followed, the `shift 2` below failed without consuming
                # anything, and the loop spun forever instead of launching.
                args+=("$@")
                break
                ;;
            -t|--task)
                # Refuse rather than continue with an empty task name. `yn` is
                # `yolo -t`, i.e. `claude --dangerously-skip-permissions -t`, so
                # a bare `yn` reaches here with no value — and carrying on would
                # launch a skip-permissions session that the user never
                # completed the command for. (Before this guard existed the same
                # input hung instead: `shift 2` with one argument left shifts
                # nothing and returns non-zero, spinning the loop forever.)
                if [[ $# -lt 2 ]]; then
                    echo "claude: $1 requires a task name" >&2
                    return 2
                fi
                task_name="$2"
                shift 2
                ;;
            *)
                args+=("$1")
                shift
                ;;
        esac
    done

    # Auto-cd to git root so plansDirectory: "plans" resolves correctly
    # Must happen before task ID generation so auto-name reflects git root, not subdir
    # Use realpath to resolve symlinks — git rev-parse --show-toplevel returns physical paths
    local git_root physical_cwd
    git_root=$(git rev-parse --show-toplevel 2>/dev/null)
    physical_cwd=$(realpath "$PWD" 2>/dev/null || pwd -P)
    if [[ -n "$git_root" && "$physical_cwd" != "$git_root" ]]; then
        echo "claude: moving to git root: $git_root"
        cd "$git_root" || true
    fi

    # Task list ID generation moved to just before the launch (see below), so
    # no early return can leave a half-configured export behind.

    # --channels only applies to session mode, not subcommands (doctor, auth, etc.).
    # Derive subcommand list from `claude --help`, cached per version to avoid 200ms/call.
    local _is_session=true
    # Find first positional arg, skipping flags and their values.
    # Known value-consuming flags are skipped so e.g. `claude --model sonnet doctor`
    # correctly identifies `doctor` (not `sonnet`) as the first positional.
    local _first_positional="" _skip_next=false
    for _a in "${args[@]}"; do
        if [[ "$_skip_next" == true ]]; then _skip_next=false; continue; fi
        # Everything after `--` is prompt text, never a subcommand name. Without
        # this the scan skipped the terminator as just another dash-argument and
        # then read the seed itself: a spawned session seeded with exactly
        # "doctor" was classified as `claude doctor`, so --channels was dropped
        # and the session came up unable to receive messages.
        if [[ "$_a" == "--" ]]; then
            _first_positional=""
            break
        fi
        case "$_a" in
            --model|--agent|--agents|--resume|-r|--permission-mode|--settings| \
            --system-prompt|--system-prompt-file|--append-system-prompt|--append-system-prompt-file| \
            --effort|--mcp-config|--output-format|--input-format|--max-budget-usd| \
            --json-schema|--fallback-model|--debug-file|-n|--name|-d|--debug| \
            --add-dir|--allowedTools|--allowed-tools|--disallowedTools|--disallowed-tools| \
            --betas|--file|--plugin-dir|--from-pr)
                _skip_next=true; continue ;;
            -*) continue ;;
        esac
        _first_positional="$_a"; break
    done
    if [[ -n "$_first_positional" ]]; then
        local _cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-wrapper"
        local _version; _version=$(claude --version 2>/dev/null | head -1)
        if [[ -n "$_version" ]]; then
            local _cache_file="$_cache_dir/subcommands-${_version//[^a-zA-Z0-9.]/_}"
            local _subcmds
            if [[ -f "$_cache_file" ]]; then
                _subcmds=$(<"$_cache_file")
            else
                # Extract subcommands, handling aliases (plugin|plugins) and hyphens (setup-token)
                _subcmds=$(claude --help 2>&1 | grep -E '^\s+[a-z][a-z|_-]*\s' | awk '{print $1}' | grep -v '^prompt$' | tr '|' '\n' | tr '\n' '|')
                if [[ -n "$_subcmds" ]]; then
                    mkdir -p "$_cache_dir" && printf '%s' "$_subcmds" > "$_cache_file" 2>/dev/null
                fi
            fi
            # Check if first positional matches a known subcommand
            if [[ -n "$_subcmds" && "|${_subcmds}" == *"|${_first_positional}|"* ]]; then
                _is_session=false
            fi
        fi
    fi

    # Per-project channels: auto-detect and enable (session mode only)
    if [[ "$_is_session" == true ]]; then
        local channels=()
        if [[ -n "${DOTFILES_TELEGRAM_BOT_SECRET:-}" ]]; then
            export TELEGRAM_STATE_DIR="${TELEGRAM_STATE_DIR:-$PWD/.claude/channels/telegram}"
            if ! _claude_prepare_telegram_state "$TELEGRAM_STATE_DIR" "$DOTFILES_TELEGRAM_BOT_SECRET"; then
                return 1
            fi
            channels+=(plugin:telegram@claude-plugins-official)
        elif [[ -f ".claude/channels/telegram/.env" ]]; then
            export TELEGRAM_STATE_DIR="${TELEGRAM_STATE_DIR:-$PWD/.claude/channels/telegram}"
            channels+=(plugin:telegram@claude-plugins-official)
        else
            unset TELEGRAM_STATE_DIR
            unset DOTFILES_TELEGRAM_BOT_SECRET
        fi
        if [[ -f ".claude/channels/imessage/access.json" ]]; then
            export IMESSAGE_STATE_DIR="${IMESSAGE_STATE_DIR:-$PWD/.claude/channels/imessage}"
            channels+=(plugin:imessage@claude-plugins-official)
        elif command -v imessage-mcp &>/dev/null; then
            # No project-local channel — use global default
            unset IMESSAGE_STATE_DIR
            channels+=(plugin:imessage@claude-plugins-official)
        fi
        if [[ ${#channels[@]} -gt 0 ]]; then
            # Insert BEFORE a `--` terminator when the caller supplied one.
            # Appending unconditionally put these flags AFTER `--`, where they
            # stop being options and become prompt text — silently: the session
            # came up with no channel and the extra words glued onto the prompt.
            # claude-spawn passes `--` so that a dash-leading seed prompt cannot
            # turn into a flag, and any other caller doing the same is entitled
            # to the same handling.
            local -a _pre _post
            local _seen_term=false _a
            for _a in "${args[@]}"; do
                if [[ "$_seen_term" == false && "$_a" == "--" ]]; then
                    _seen_term=true
                fi
                if [[ "$_seen_term" == true ]]; then
                    _post+=("$_a")
                else
                    _pre+=("$_a")
                fi
            done
            args=("${_pre[@]}" --channels "${channels[@]}" "${_post[@]}")
        fi
    fi

    # Remote Control requires api.anthropic.com: the model-router's global
    # ANTHROPIC_BASE_URL redirect disables it, and Claude Code exempts
    # _CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL from Remote Control. A CLI
    # --settings file outranks the user-settings env block, so interactive
    # sessions get rc-direct-settings.json, which blanks the redirect. Skipped
    # for print mode and subcommands (no RC there), when the caller brought
    # their own --settings, when GPT is the MAIN model (that needs the router;
    # GPT subagents are likewise unavailable under the override — use
    # `claude -p --model gpt-5.6-sol` for those), for --version/--help (the
    # subcommand probe above calls `claude --version` recursively, and a
    # prepended flag must not shift what that probe's stub or binary sees
    # first), and under CLAUDE_RC_OVERRIDE=0 (documented opt-out). Three
    # subcommands DO get it: `remote-control`/`rc` (that launcher cannot work
    # on a redirected base URL) and `agents` (its --settings applies to the
    # agent view AND to the sessions it dispatches — per `claude agents
    # --help` — so this is what gives dispatched sessions RC; dispatch runs
    # via the daemon, outside this wrapper, and can't be fixed there). For
    # these the override applies regardless of flags — `remote-control
    # --help` keeps it; only a caller-supplied --settings (which `agents`
    # legitimately takes), the opt-out, or a missing file skip it.
    # PREPENDED, never appended: a caller-supplied `--` terminator would
    # strand an appended option as prompt text — the same trap --channels
    # fell into.
    local _rc_subcmd=false
    if [[ "$_first_positional" == "remote-control" || "$_first_positional" == "rc" \
          || "$_first_positional" == "agents" ]]; then
        _rc_subcmd=true
    fi
    if [[ ( "$_is_session" == true || "$_rc_subcmd" == true ) \
          && "${CLAUDE_RC_OVERRIDE:-1}" != "0" ]]; then
        local _rc_settings="$HOME/.claude/rc-direct-settings.json"
        # Missing file → skip silently: non-deployed machines must not break.
        if [[ -f "$_rc_settings" ]]; then
            local _add_rc=true _rc_prev="" _b
            for _b in "${args[@]}"; do
                if [[ "$_rc_prev" == "--model" ]]; then
                    _rc_prev=""
                    if [[ "$_b" == gpt-5.6* ]]; then _add_rc=false; break; fi
                    continue
                fi
                case "$_b" in
                    --) break ;;
                    -p|--print) _add_rc=false; break ;;
                    -v|--version|-h|--help)
                        if [[ "$_rc_subcmd" == false ]]; then _add_rc=false; break; fi ;;
                    --settings|--settings=*) _add_rc=false; break ;;
                    --model=gpt-5.6*) _add_rc=false; break ;;
                    --model) _rc_prev="--model" ;;
                esac
            done
            if [[ "$_add_rc" == true ]]; then
                args=(--settings="$_rc_settings" "${args[@]}")
            fi
        fi
    fi

    # Task list ID, scoped to this launch and restored afterwards. An export
    # that outlives the launch follows the shell across `cd`s and into the
    # tmux server env, so sessions in unrelated repos silently join one task
    # list (claude-spawn blanks the var for the same reason). Inherited values
    # are honored only with CLAUDE_CODE_TASK_LIST_PIN=1 (claude-new,
    # claude-with, claude-last): an unpinned inherited ID is a stale leak
    # from a pre-fix shell or the tmux server environment.
    local _prev_tlid_set=0 _prev_tlid=""
    if [[ -n "${CLAUDE_CODE_TASK_LIST_ID+x}" ]]; then
        _prev_tlid_set=1
        _prev_tlid="$CLAUDE_CODE_TASK_LIST_ID"
    fi
    local _tl_timestamp _tl_suffix
    _tl_timestamp=$(date -u +%Y%m%d_%H%M%S)
    if [[ -n "$task_name" ]]; then
        # Explicit -t flag: always generate fresh with custom name
        export CLAUDE_CODE_TASK_LIST_ID="${_tl_timestamp}_UTC_${task_name}"
    elif [[ "${CLAUDE_CODE_TASK_LIST_PIN:-}" != 1 || -z "$CLAUDE_CODE_TASK_LIST_ID" ]]; then
        # Auto-generate from directory name (basename of git root — distinct
        # per worktree; share deliberately with -t/claude-with when needed)
        _tl_suffix=$(basename "$PWD" | tr ' ' '_')
        export CLAUDE_CODE_TASK_LIST_ID="${_tl_timestamp}_UTC_${_tl_suffix}"
    fi

    activate_venv
    command claude "${args[@]}"
    local _claude_rc=$?
    if (( _prev_tlid_set )); then
        export CLAUDE_CODE_TASK_LIST_ID="$_prev_tlid"
    else
        unset CLAUDE_CODE_TASK_LIST_ID
    fi
    return $_claude_rc
}
# Canonical skip-permissions launcher. ccy/ccd are kept as back-compat shims.
alias yolo='claude --dangerously-skip-permissions'
alias resume='claude --resume'
# NOT aliasing `continue` — it's a shell keyword; zsh expands aliases in command
# position even inside interactively-typed loops, so the alias would hijack them.
alias cont='claude --continue'
alias yn='yolo -t'  # yn <name>: yolo with task name

# Artifact dirs checked across worktree commands (port, remove, clean)
_CW_ARTIFACT_DIRS=(out logs data results experiments)

# worktree commands
_cw_launch() {
  # Shared implementation for cw/cwy — idempotent worktree launcher
  # Usage: _cw_launch [--yolo] [name] [extra args...]
  local yolo=false
  if [[ "$1" == "--yolo" ]]; then yolo=true; shift; fi

  local name=""
  if [[ $# -gt 0 && "$1" != -* ]]; then
    name="$1"; shift
  fi

  local extra=("$@")
  $yolo && extra=("--dangerously-skip-permissions" "${extra[@]}")

  # Resume existing worktree if it exists
  if [[ -n "$name" ]]; then
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -z "$git_root" ]]; then
      echo "cw: not in a git repository" >&2
      return 1
    fi
    local wt_path="$git_root/.claude/worktrees/$name"

    if [[ -d "$wt_path" ]]; then
      local session="worktree-$name"

      # Case 1: tmux session alive → attach/switch
      # Use = prefix for exact session name match (prevents prefix matching)
      if tmux has-session -t "=$session" 2>/dev/null; then
        echo "Attaching to session: $session"
        if [[ -n "$TMUX" ]]; then
          tmux switch-client -t "=$session"
        else
          tmux attach -t "=$session"
        fi
        return
      fi

      # Case 2: worktree exists, no tmux → create session, run claude (no --tmux)
      echo "Resuming worktree: $name"
      local cmd="claude"
      for arg in "${extra[@]}"; do
        cmd+=" $(printf '%q' "$arg")"
      done
      if [[ -n "$TMUX" ]]; then
        tmux new-session -d -s "$session" -c "$wt_path" "$cmd; exec \$SHELL"
        tmux switch-client -t "=$session"
      else
        tmux new-session -s "$session" -c "$wt_path" "$cmd; exec \$SHELL"
      fi
      return
    fi
  fi

  # Case 3: no existing worktree → create new (original behavior)
  local wt_args=("--worktree")
  [[ -n "$name" ]] && wt_args+=("$name")
  claude "${wt_args[@]}" --tmux "${extra[@]}"
}

cw() { _cw_launch "$@"; }
cwy() { _cw_launch --yolo "$@"; }

alias cwl='git worktree list'

cwport() {
  # Port gitignored artifacts from a worktree to main tree
  # Usage: cwport <name> [dirs...]
  #   cwport refactor-auth              # ports default dirs
  #   cwport refactor-auth out logs     # ports specific dirs
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: cwport <worktree-name> [dirs...]"
    return 1
  fi
  shift

  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$git_root" ]]; then
    echo "cwport: not in a git repository" >&2
    return 1
  fi
  local wt_path="$git_root/.claude/worktrees/$name"
  if [[ ! -d "$wt_path" ]]; then
    echo "cwport: worktree not found: $wt_path" >&2
    return 1
  fi

  local dirs
  if [[ $# -gt 0 ]]; then
    dirs=("$@")
  else
    dirs=("${_CW_ARTIFACT_DIRS[@]}")
  fi
  local dest
  dest="$git_root/out/worktree-${name}-$(date -u +%Y%m%d_%H%M%S)"
  local ported=0

  for dir in "${dirs[@]}"; do
    if [[ -d "$wt_path/$dir" ]]; then
      mkdir -p "$dest"
      echo "Porting $dir/ → $dest/$dir/"
      cp -r "$wt_path/$dir" "$dest/$dir"
      ported=$(( ported + 1 ))
    fi
  done

  if [[ $ported -eq 0 ]]; then
    echo "No artifacts found in: ${dirs[*]}"
  else
    echo "Ported $ported dir(s) to $dest"
  fi
}

cwmerge() {
  # Merge a worktree branch into the parent branch
  # Works from main tree OR from inside a worktree (auto-detects)
  # Auto-aborts on conflict, suggests /merge-worktree skill for AI resolution
  # Usage: cwmerge [worktree-name]  (name optional when inside a worktree)
  local name="$1"
  local merge_dir=""

  # Auto-detect if we're inside a worktree
  local git_dir common_dir
  git_dir=$(git rev-parse --git-dir 2>/dev/null)
  common_dir=$(git rev-parse --git-common-dir 2>/dev/null)

  if [[ "$git_dir" != "$common_dir" ]]; then
    # We're inside a worktree — infer name from branch, merge into main tree
    if [[ -z "$name" ]]; then
      local current_branch
      current_branch=$(git rev-parse --abbrev-ref HEAD)
      name="${current_branch#worktree-}"
      if [[ "$name" == "$current_branch" ]]; then
        # Branch doesn't have worktree- prefix, use directory name
        name=$(basename "$(git rev-parse --show-toplevel)")
      fi
    fi
    # Find main worktree path (first entry in worktree list)
    merge_dir=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
    echo "Inside worktree — merging into main tree at $merge_dir"
  fi

  if [[ -z "$name" ]]; then
    echo "Usage: cwmerge <worktree-name>"
    echo "  (or run from inside a worktree to auto-detect)"
    return 1
  fi

  local branch="worktree-$name"
  if ! git rev-parse --verify "$branch" &>/dev/null; then
    echo "cwmerge: branch not found: $branch" >&2
    return 1
  fi

  # Determine target branch and merge directory
  local target_branch
  if [[ -n "$merge_dir" ]]; then
    target_branch=$(git -C "$merge_dir" rev-parse --abbrev-ref HEAD)
  else
    merge_dir=$(git rev-parse --show-toplevel)
    target_branch=$(git rev-parse --abbrev-ref HEAD)
  fi

  local ahead
  ahead=$(git rev-list --count "$target_branch..$branch" 2>/dev/null || echo 0)

  if [[ "$ahead" -eq 0 ]]; then
    echo "Already up to date ($branch has no new commits vs $target_branch)."
    return 0
  fi

  echo "Merging $branch ($ahead commit(s)) into $target_branch..."
  if git -C "$merge_dir" merge --no-edit "$branch"; then
    echo "Merged successfully."
  else
    git -C "$merge_dir" merge --abort
    echo "Conflict — merge aborted (repo is clean). Conflicting files:"
    git diff --name-only "$target_branch" "$branch"
    echo ""
    echo "To resolve with Claude:  /merge-worktree"
    echo "To resolve manually:     git -C $merge_dir merge worktree-$name"
    echo "To accept worktree version: git -C $merge_dir merge -X theirs worktree-$name"
    return 1
  fi
}

cwrm() {
  # Remove a Claude-created worktree: merge branch → remove dir → delete branch
  # Merges into current branch by default (use --no-merge to skip)
  # Warns if gitignored artifacts exist (use cwport first or --force)
  local force=false no_merge=false
  while [[ "$1" == --* ]]; do
    case "$1" in
      --force) force=true; shift ;;
      --no-merge) no_merge=true; shift ;;
      *) break ;;
    esac
  done

  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Usage: cwrm [--force] [--no-merge] <worktree-name>"
    echo ""; cwl; return 1
  fi

  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$git_root" ]]; then
    echo "cwrm: not in a git repository" >&2
    return 1
  fi
  local wt_path="$git_root/.claude/worktrees/$name"
  if [[ ! -d "$wt_path" ]]; then
    echo "cwrm: worktree not found: $wt_path" >&2
    cwl; return 1
  fi

  # Check for gitignored artifacts
  if ! $force; then
    local artifacts=()
    for dir in "${_CW_ARTIFACT_DIRS[@]}"; do
      [[ -d "$wt_path/$dir" ]] && artifacts+=("$dir/")
    done
    if [[ ${#artifacts[@]} -gt 0 ]]; then
      echo "Warning: worktree has artifacts: ${artifacts[*]}"
      echo "  Port first: cwport $name"
      echo "  Or force:   cwrm --force $name"
      return 1
    fi
  fi

  # Merge worktree branch into current branch (default)
  if ! $no_merge; then
    cwmerge "$name" || return 1
  fi

  echo "Removing worktree: $wt_path"
  if $force; then
    git worktree remove --force "$wt_path" && echo "Worktree removed."
  else
    git worktree remove "$wt_path" && echo "Worktree removed."
  fi

  local branch="worktree-$name"
  if git rev-parse --verify "$branch" &>/dev/null; then
    echo "Deleting branch: $branch"
    git branch -D "$branch"
  fi
}

cwclean() {
  # Remove clean worktrees (no uncommitted changes, no artifacts)
  # Usage: cwclean [--dry-run]
  local dry_run=false
  [[ "$1" == "--dry-run" ]] && dry_run=true

  git worktree prune  # clean up metadata for deleted dirs

  local git_root
  git_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$git_root" ]]; then
    echo "cwclean: not in a git repository" >&2
    return 1
  fi
  local wt_dir="$git_root/.claude/worktrees"

  if [[ ! -d "$wt_dir" ]] || [[ -z "$(ls -A "$wt_dir" 2>/dev/null)" ]]; then
    echo "No Claude worktrees found."
    return 0
  fi

  local cleaned=0 skipped=0 name wt_status has_artifacts
  for wt in "$wt_dir"/*/; do
    [[ ! -d "$wt" ]] && continue
    name=$(basename "$wt")
    wt_status="active"

    # Check if tmux session for this worktree is alive (= for exact match)
    if ! tmux has-session -t "=worktree-$name" 2>/dev/null; then
      if git -C "$wt" diff --quiet HEAD 2>/dev/null && \
         [[ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ]]; then
        wt_status="clean"
      else
        wt_status="dirty"
      fi
    fi

    has_artifacts=""
    for dir in "${_CW_ARTIFACT_DIRS[@]}"; do
      [[ -d "$wt/$dir" ]] && has_artifacts=" +artifacts"
    done

    if [[ "$wt_status" == "clean" ]] && [[ -z "$has_artifacts" ]]; then
      if $dry_run; then
        printf "  %-30s [would remove]\n" "$name"
      else
        cwrm --force --no-merge "$name"
      fi
      cleaned=$(( cleaned + 1 ))
    else
      printf "  %-30s [%s%s] — kept\n" "$name" "$wt_status" "$has_artifacts"
      skipped=$(( skipped + 1 ))
    fi
  done

  if $dry_run; then
    echo "Would remove $cleaned worktree(s), keep $skipped."
  elif [[ $cleaned -gt 0 || $skipped -gt 0 ]]; then
    echo "Removed $cleaned, kept $skipped (dirty/active/has artifacts)."
  fi
}

# -------------------------------------------------------------------
# AI CLI Tools
# -------------------------------------------------------------------
# Health check for all AI CLI tools
alias ai-check='echo "Checking AI CLI tools..." && claude --version 2>/dev/null && gemini --version 2>/dev/null && codex --version 2>/dev/null'

# Log sandbox denials for a command (macOS/Linux)
codex-denials() {
  if [ "$#" -eq 0 ]; then
    echo "Usage: codex-denials <command> [args...]"
    echo "Example: codex-denials git commit -m \"message\""
    return 1
  fi

  if [[ "$OSTYPE" == darwin* ]]; then
    local tmpdir=""
    if [ -w "$PWD" ]; then
      tmpdir="${PWD}/tmp/codex"
      mkdir -p "$tmpdir"
    fi
    TMPDIR="${tmpdir:-${TMPDIR:-/tmp}}" TEMP="${tmpdir:-${TEMP:-/tmp}}" TMP="${tmpdir:-${TMP:-/tmp}}" \
      command codex sandbox macos --full-auto --log-denials -- "$@"
  else
    command codex sandbox linux --log-denials -- "$@"
  fi
}

# Claude Code Task List Management
# Start new work with custom description (overrides auto-generated name)
claude-new() {
  local description="$1"
  if [ -z "$description" ]; then
    echo "Usage: claude-new <description>"
    echo "Example: claude-new oauth-refactor"
    return 1
  fi

  local timestamp
  timestamp=$(date -u +%Y%m%d_%H%M%S)
  local task_list_id="${timestamp}_UTC_${description}"

  echo "Starting Claude with task list: $task_list_id"
  echo "export CLAUDE_CODE_TASK_LIST_ID=$task_list_id" > .claude_task_list_id

  # Prefix-env, not export: zsh restores it after the function returns, so
  # nothing lingers in the shell to leak into later launches in other repos.
  CLAUDE_CODE_TASK_LIST_ID="$task_list_id" CLAUDE_CODE_TASK_LIST_PIN=1 claude
}

# Resume last task list in current directory
claude-last() {
  if [ -f .claude_task_list_id ]; then
    local task_list_id
    task_list_id=$(sed -n 's/^export CLAUDE_CODE_TASK_LIST_ID=//p' .claude_task_list_id | head -n1)
    if [ -z "$task_list_id" ]; then
      echo "Could not parse .claude_task_list_id"
      return 1
    fi
    echo "Resuming task list: $task_list_id"
    CLAUDE_CODE_TASK_LIST_ID="$task_list_id" CLAUDE_CODE_TASK_LIST_PIN=1 claude
  else
    echo "No previous task list found in this directory"
    echo "Start a new one with: claude-new <description>"
  fi
}

# List all task lists
claude-tasks-list() {
  echo "Available task lists:"
  echo ""
  if [ -d ~/.claude/tasks/ ]; then
    ls -1t ~/.claude/tasks/ | head -20
  else
    echo "(none yet)"
  fi
  echo ""
  echo "Start a new task list: claude-new <description>"
}

# Start Claude with a specific task list (by name)
claude-with() {
  local task_list_id="$1"
  if [ -z "$task_list_id" ]; then
    echo "Usage: claude-with <task-list-name>"
    echo ""
    claude-tasks-list
    return 1
  fi

  echo "Using task list: $task_list_id"
  CLAUDE_CODE_TASK_LIST_ID="$task_list_id" CLAUDE_CODE_TASK_LIST_PIN=1 claude
}

# Switch Claude Code account (full logout + login, not just restart)
alias claude-switch='claude auth logout && claude auth login'


ccusage() {
  if command -v bunx >/dev/null 2>&1; then
    bunx ccusage@latest "$@"
  elif command -v npx >/dev/null 2>&1; then
    npx ccusage@latest "$@"
  else
    echo "Error: Neither 'bunx' nor 'npx' is installed. Please install one to run 'ccusage'."
    return 1
  fi
}

# Update all AI CLI tools (delegates to update-ai-tools script)
alias ai-update='update-ai-tools'

# System package update + upgrade + cleanup (delegates to update-packages script)
# Detects: brew (macOS), apt/dnf/pacman (Linux)
alias pkg-update='update-packages'

# Auto-agent guard controls
alias auto-guard='auto-agent-guardctl status'
alias auto-approve='auto-agent-guardctl approve'
alias auto-disable='auto-agent-guardctl disable'
alias auto-enable='auto-agent-guardctl enable'
alias auto-trace='auto-agent-guardctl trace'

# Clean duplicate skills from Claude Code (plugin symlinks cause 2x entries)
alias clean-skill-dupes='"$DOT_DIR/scripts/cleanup/clean_plugin_symlinks.sh"'
