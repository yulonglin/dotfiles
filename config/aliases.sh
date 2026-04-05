# -------------------------------------------------------------------
# Source additional alias files
# -------------------------------------------------------------------
if [ -f "$DOT_DIR/config/aliases_inspect.sh" ]; then
    source "$DOT_DIR/config/aliases_inspect.sh"
fi

# -------------------------------------------------------------------
# personal
# -------------------------------------------------------------------

alias dot="cd $DOT_DIR"
alias jp="jupyter lab"
alias hn="hostname"
alias sync-gist='"$DOT_DIR/scripts/sync_gist.sh"'

# SOPS-encrypted secrets management
# On macOS, sops checks ~/Library/Application Support/sops/age/keys.txt (Go's
# os.UserConfigDir), not ~/.config/. Point it to the XDG-conventional location.
export SOPS_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"

# Thin wrapper: secrets are dotenv format but files end in .enc, so sops
# can't infer the format. This sets --input-type/--output-type once.
sops_dotenv() { sops --input-type dotenv --output-type dotenv "$@"; }

secrets-edit() {
    if ! command -v sops &>/dev/null; then echo "sops not installed — run install.sh"; return 1; fi
    sops_dotenv --config "$DOT_DIR/.sops.yaml" "$DOT_DIR/config/secrets.env.enc"
    secrets-decrypt
}
secrets-encrypt() {
    if ! command -v sops &>/dev/null; then echo "sops not installed — run install.sh"; return 1; fi
    local src="$DOT_DIR/.secrets"
    local enc="$DOT_DIR/config/secrets.env.enc"
    local sops_yaml="$DOT_DIR/.sops.yaml"
    if [[ ! -f "$src" ]]; then echo "No .secrets file at $src"; return 1; fi
    if [[ ! -f "$sops_yaml" ]]; then echo "No .sops.yaml at $sops_yaml — run secrets-init"; return 1; fi
    # Extract age public key — bypass creation rules since input (.secrets) doesn't match .enc$ regex
    local pub_key
    pub_key=$(grep -o 'age1[a-z0-9]*' "$sops_yaml" | head -1)
    if [[ -z "$pub_key" ]]; then echo "No age public key found in $sops_yaml"; return 1; fi
    echo "Encrypting $src → $enc"
    if sops_dotenv -e --config /dev/null --age "$pub_key" "$src" > "${enc}.tmp"; then
        mv "${enc}.tmp" "$enc"
        echo "Encrypted to $enc"
    else
        rm -f "${enc}.tmp"
        echo "Failed to encrypt" >&2; return 1
    fi
}
secrets-decrypt() {
    if ! command -v sops &>/dev/null; then echo "sops not installed — run install.sh"; return 1; fi
    local enc="$DOT_DIR/config/secrets.env.enc"
    local out="$DOT_DIR/.secrets"
    local sops_yaml="$DOT_DIR/.sops.yaml"
    if [[ ! -f "$enc" ]]; then echo "No encrypted secrets at $enc — run secrets-init"; return 1; fi
    if [[ ! -f "$sops_yaml" ]]; then echo "No .sops.yaml at $sops_yaml — run secrets-init"; return 1; fi
    echo "Decrypting $enc → $out"
    if (umask 077 && sops_dotenv -d --config "$sops_yaml" "$enc" > "${out}.tmp"); then
        mv "${out}.tmp" "$out"
        echo "Decrypted to $out"
    else
        rm -f "${out}.tmp"
        echo "Failed to decrypt (sops -d --config $sops_yaml $enc)" >&2; return 1
    fi
}
secrets-init() {
    local age_dir="$HOME/.config/sops/age"
    local age_key="$age_dir/keys.txt"
    local sops_yaml="$DOT_DIR/.sops.yaml"
    local enc="$DOT_DIR/config/secrets.env.enc"

    echo "Config: age_key=$age_key"
    echo "Config: sops_yaml=$sops_yaml"
    echo "Config: enc=$enc"

    if [[ ! -f "$age_key" ]]; then
        mkdir -p "$age_dir"
        age-keygen -o "$age_key" 2>&1
        chmod 600 "$age_key"
        echo "Generated age key at $age_key"
    else
        echo "Age key already exists at $age_key"
    fi

    local pub_key
    pub_key=$(grep -o 'age1[a-z0-9]*' "$age_key" | head -1)
    echo "Public key: ${pub_key:0:20}..."

    if [[ ! -f "$sops_yaml" ]] || grep -q 'age1\.\.\.' "$sops_yaml"; then
        cat > "$sops_yaml" <<YAML
creation_rules:
  - path_regex: \\.enc$
    age: "$pub_key"
YAML
        echo "Created $sops_yaml with public key"
    else
        # Warn if local key doesn't match the key in .sops.yaml
        local config_key
        config_key=$(grep -o 'age1[a-z0-9]*' "$sops_yaml" | head -1)
        if [[ -n "$config_key" && "$config_key" != "$pub_key" ]]; then
            echo "⚠️  Key mismatch! Local age key does not match $sops_yaml"
            echo "  Local key:      ${pub_key:0:30}..."
            echo "  .sops.yaml key: ${config_key:0:30}..."
            echo "  You won't be able to decrypt existing secrets with this key"
            echo "  To fix: paste the original age key from Bitwarden into $age_key"
        else
            echo "$sops_yaml already exists, skipping"
        fi
    fi

    if [[ ! -s "$enc" ]]; then
        local tmpfile="${TMPDIR:-/tmp}/secrets_template.env"
        printf '%s\n' \
            "# Encrypted API keys (edit with: secrets-edit)" \
            "PLACEHOLDER=replace_me" \
            "# ANTHROPIC_API_KEY=" \
            "# OPENAI_API_KEY=" \
            "# HF_TOKEN=" \
            "# GITHUB_TOKEN=" \
            > "$tmpfile"
        echo "Running: sops -e --config /dev/null --age <key> $tmpfile > $enc"
        if sops -e --config /dev/null --age "$pub_key" "$tmpfile" > "${enc}.tmp"; then
            mv "${enc}.tmp" "$enc"
            echo "Created $enc — edit with: secrets-edit"
        else
            rm -f "${enc}.tmp"
            echo "Failed to encrypt (sops -e --config /dev/null --age ... $tmpfile)" >&2
        fi
        rm -f "$tmpfile"
    else
        echo "Encrypted secrets already exist at $enc"
    fi

    echo ""
    echo "Next steps:"
    echo "  1. secrets-edit          # Add your API keys"
    echo "  2. sync-gist             # Sync SSH config + git identity"
    echo "  3. source ~/.zshrc       # Load secrets into shell"
}
secrets-init-project() {
    local sops_yaml=".sops.yaml"
    local enc="secrets.env.enc"
    local envrc=".envrc"
    local age_key="$HOME/.config/sops/age/keys.txt"

    if [[ ! -f "$age_key" ]]; then
        echo "No age key found at $age_key — run secrets-init first"
        return 1
    fi

    local pub_key
    pub_key=$(grep -o 'age1[a-z0-9]*' "$age_key" | head -1)
    if [[ -z "$pub_key" ]]; then
        echo "Could not extract public key from $age_key" >&2; return 1
    fi
    echo "Public key: ${pub_key:0:20}..."

    if [[ ! -f "$sops_yaml" ]]; then
        cat > "$sops_yaml" <<YAML
creation_rules:
  - path_regex: \\.enc$
    age: "$pub_key"
YAML
        echo "Created $sops_yaml in $(pwd)"
    fi

    if [[ ! -s "$enc" ]]; then
        local tmpfile="${TMPDIR:-/tmp}/proj_secrets.env"
        printf '%s\n' "# Project secrets (edit with: sops $enc)" "PLACEHOLDER=replace_me" > "$tmpfile"
        echo "Running: sops -e --config /dev/null --age <key> $tmpfile > $enc"
        if sops -e --config /dev/null --age "$pub_key" "$tmpfile" > "${enc}.tmp"; then
            mv "${enc}.tmp" "$enc"
            echo "Created $enc"
        else
            rm -f "${enc}.tmp"
            echo "Failed to encrypt (sops -e --config /dev/null --age ... $tmpfile)" >&2
        fi
        rm -f "$tmpfile"
    fi

    if [[ ! -f "$envrc" ]]; then
        if [[ -f "$DOT_DIR/config/envrc_sops_template" ]]; then
            cp "$DOT_DIR/config/envrc_sops_template" "$envrc"
        else
            printf '%s\n' '# Auto-decrypt SOPS secrets on cd' \
                'if command -v sops &>/dev/null && [ -f secrets.env.enc ]; then' \
                '    dotenv <(sops -d --input-type dotenv --output-type dotenv --config .sops.yaml secrets.env.enc 2>/dev/null)' \
                'fi' > "$envrc"
        fi
        echo "Created $envrc — run: direnv allow"
    fi

    echo "Done. Edit secrets: sops --config $sops_yaml $enc"
}
alias sync-snippets='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" sync'
alias export-snippets='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" export'
alias snippets-diff='uv run --with ruamel.yaml "$DOT_DIR/scripts/sync_text_replacements.py" diff'

# Sync Mouseless UI config changes back to dotfiles (macOS only)
if [[ "$(uname)" == "Darwin" ]]; then
    sync-mouseless() {
        local src="$HOME/Library/Containers/net.sonuscape.mouseless/Data/.mouseless/configs/config.yaml"
        local dst="$DOT_DIR/config/mouseless/config.yaml"
        if [[ ! -f "$src" ]]; then
            echo "Mouseless config not found at $src"
            return 1
        fi
        if ! python3 -c "import yaml" 2>/dev/null; then
            echo "PyYAML not installed. Run: pip3 install pyyaml" >&2
            return 1
        fi
        python3 - "$src" "$dst" <<'PYEOF'
import sys, yaml
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    cfg = yaml.safe_load(f)
cfg.pop('keyboard_layout', None)
cfg.pop('app_version', None)
with open(dst, 'w') as f:
    yaml.dump(cfg, f, allow_unicode=True, sort_keys=False, default_flow_style=False)
PYEOF
        echo "Synced Mouseless config → $dst (stripped keyboard_layout, app_version)"
    }
fi

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
            -t|--task)
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

    # Generate task list ID: -t flag always overrides, otherwise keep existing or auto-generate
    if [[ -n "$task_name" ]]; then
        # Explicit -t flag: always generate fresh with custom name
        local timestamp
        timestamp=$(date -u +%Y%m%d_%H%M%S)
        export CLAUDE_CODE_TASK_LIST_ID="${timestamp}_UTC_${task_name}"
    elif [[ -z "$CLAUDE_CODE_TASK_LIST_ID" ]]; then
        # No existing ID: auto-generate from directory name
        local suffix timestamp
        suffix=$(basename "$PWD" | tr ' ' '_')
        timestamp=$(date -u +%Y%m%d_%H%M%S)
        export CLAUDE_CODE_TASK_LIST_ID="${timestamp}_UTC_${suffix}"
    fi
    # else: keep existing CLAUDE_CODE_TASK_LIST_ID (set by claude-new, claude-with, etc.)

    # Per-project channels: auto-detect and enable
    local channels=()
    if [[ -f ".claude/channels/telegram/.env" ]]; then
        export TELEGRAM_STATE_DIR="$PWD/.claude/channels/telegram"
        channels+=(plugin:telegram@claude-plugins-official)
    else
        unset TELEGRAM_STATE_DIR
    fi
    if [[ -f ".claude/channels/imessage/.env" ]] || command -v imessage-mcp &>/dev/null; then
        channels+=(plugin:imessage@claude-plugins-official)
    fi
    if [[ ${#channels[@]} -gt 0 ]]; then
        args+=(--channels "${channels[@]}")
    fi

    activate_venv
    command claude "${args[@]}"
}
# cc* — claude code aliases (no worktree, no tmux)
alias ccy='claude --dangerously-skip-permissions'   # cc yolo
alias ccd='claude --dangerously-skip-permissions'   # cc dangerous
alias yolo='claude --dangerously-skip-permissions'
alias resume='yolo --resume'
alias cont='yolo --continue'
alias continue='yolo --continue'
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
# general
# -------------------------------------------------------------------

alias cl="clear"

# file and directories
alias rm='rm -i'
alias rmd='rm -rf'
alias cp='cp -i'
alias mv='mv -i'
alias mkdir='mkdir -p'

# find/read files
alias h='head'
alias t='tail'
# alias rl="readlink -f"
# Note: NOT aliasing find="fd" - they have different syntax
# Use fd directly, or findfile/findf aliases from modern_tools.sh
alias ff='fd --type f'
# fd-find package on Debian/Ubuntu installs as 'fdfind'
if command -v fdfind &>/dev/null && ! command -v fd &>/dev/null; then
    alias fd='fdfind'
fi
alias which='type -a'

# storage
alias du='du -kh' # file space
alias df='df -kTh' # disk space
alias usage='du -sh * 2>/dev/null | sort -rh'
alias dus='du -sckx * | sort -nr'

# add to path
function add_to_path() {
    p=$1
    if [[ "$PATH" != *"$p"* ]]; then
      export PATH="$p:$PATH"
    fi
}

#
#-------------------------------------------------------------
# cd
#-------------------------------------------------------------

# Auto-activate .venv when cd'ing into a directory with one
cd() {
    builtin cd "$@" || return
    activate_venv
}

alias c='cd'
alias ..='cd ..'
alias ...='cd ../../'
alias ....='cd ../../../'
alias .2='cd ../../'
alias .3='cd ../../../'
alias .4='cd ../../../../'
alias .5='cd ../../../../..'
# Only set / alias in ZSH (causes issues in bash)
if [ -n "$ZSH_VERSION" ]; then
  alias /='cd /'
fi

alias d='dirs -v'
alias 1='cd -1'
alias 2='cd -2'
alias 3='cd -3'
alias 4='cd -4'
alias 5='cd -5'
alias 6='cd -6'
alias 7='cd -7'
alias 8='cd -8'
alias 9='cd -9'

alias dotfiles='cd $CODE_DIR/dotfiles'
alias code='cd $CODE_DIR'
alias writing='cd $WRITING_DIR'
alias scratch='cd $SCRATCH_DIR'
alias projects='cd $PROJECTS_DIR'
alias website='cd $WRITING_DIR/${DOTFILES_WEBSITE:-yulonglin.github.io}'

# Quick open in editor (functions instead of aliases so zsh-syntax-highlighting recognizes them)
edit-dotfiles()  { ${=EDITOR} "$DOT_DIR"; }
edit-ssh()       { ${=EDITOR} ~/.ssh/config; }
edit-claude()    { ${=EDITOR} "$DOT_DIR/claude/settings.json"; }
edit-profiles()  { ${=EDITOR} "$DOT_DIR/claude/templates/contexts/profiles.yaml"; }
edit-voiceink()  { ${=EDITOR} "$DOT_DIR/config/transcription/voiceink/macOS/prompts/"; }

#-------------------------------------------------------------
# git
#-------------------------------------------------------------

alias g="git"
alias gcl="git clone"
alias ga="git add"
alias gaa="git add ."
alias gau="git add -u"
alias gc="git commit -m"
alias gp="git push"
alias gpf="git push --force-with-lease"
alias gpo='git push origin $(git_current_branch)'
alias gpsup='git push --set-upstream origin $(git_current_branch)'

alias gg='gitui'
alias glog='git log --oneline --all --graph --decorate'
alias gl='git log --oneline -20'

alias gf="git fetch"
alias gpl="git pull"

alias grb="git rebase"
alias grbm='git rebase $(git_main_branch)'
alias grbc="git rebase --continue"
alias grbs="git rebase --skip"
alias grba="git rebase --abort"
alias grbi="git rebase -i"

alias gd="git diff"
alias gds="git diff --staged"
alias gdt="git difftool"
alias gs="git status"

alias gco="git checkout"
alias gcb="git checkout -b"
alias gcm='git checkout $(git_main_branch)'
alias gsw="git switch"
alias gswc="git switch -c"

alias gm="git merge"

alias grhead="git reset HEAD^"
alias grhard='git fetch origin && git reset --hard "origin/$(git_current_branch)"'

alias gb="git branch"
alias gba="git branch -a"
alias gbd="git branch -d"
alias gbD="git branch -D"

alias gst="git stash"
alias gstp="git stash pop"
alias gsta="git stash apply"
alias gstd="git stash drop"
alias gstc="git stash clear"
alias gstl="git stash list"

alias gcp="git cherry-pick"
alias gcpa="git cherry-pick --abort"
alias gcpc="git cherry-pick --continue"

alias grv="git remote -v"

alias ggsup='git branch --set-upstream-to=origin/$(git_current_branch)'

#-------------------------------------------------------------
# tmux
#-------------------------------------------------------------

alias ta="tmux attach"
alias taa="tmux attach -t"
alias tad="tmux attach -d -t"
alias td="tmux detach"
alias tn="tmux new-session -s"
alias ts="tmux new-session -s"
alias tl="tmux list-sessions"
alias tkill="tmux kill-server"
alias tdel="tmux kill-session -t"

# ls/tree aliases → config/modern_tools.sh (single source of truth)

#-------------------------------------------------------------
# chmod
#-------------------------------------------------------------

chw () {
  if [ "$#" -eq 1 ]; then
    chmod a+w $1
  else
    echo "Usage: chw <dir>" >&2
  fi
}
chx () {
  if [ "$#" -eq 1 ]; then
    chmod a+x $1
  else
    echo "Usage: chx <dir>" >&2
  fi
}

#-------------------------------------------------------------
# env
#-------------------------------------------------------------
alias sv="source .venv/bin/activate"
alias de="deactivate"
alias ma="micromamba activate"
alias md="micromamba deactivate"

# -------------------------------------------------------------------
# Slurm
# -------------------------------------------------------------------
alias q='squeue -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'
alias qw='watch squeue -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'
alias qq='squeue -u $(whoami) -o "%.18i %.9P %.8j %.8u %.2t %.10M %.6D %N %.10b"'
alias qtop='scontrol top'
alias qdel='scancel'
alias qnode='sinfo -Ne --Format=NodeHost,CPUsState,Gres,GresUsed'
alias qinfo='sinfo'
alias qhost='scontrol show nodes'
# Submit a quick GPU test job
alias qtest='sbatch --gres=gpu:1 --wrap="hostname; nvidia-smi"'
alias qlogin='srun --gres=gpu:1 --pty $SHELL'
# Cancel all your queued jobs
alias qclear='scancel -u $(whoami)'
# Functions to submit quick jobs with varying GPUs
# Usage: qrun 4 script.sh → submits 'script.sh' with 4 GPUs
qrun() {
  sbatch --gres=gpu:"$1" "$2"
}

# -------------------------------------------------------------------
# Pueue (local job queue + resource slices)
# -------------------------------------------------------------------
# j* prefix to avoid collision with q* (SLURM)
if command -v pueue &>/dev/null; then

  # Submit job to a group with systemd cgroup enforcement
  # Usage: jrun <group> <cmd...>
  jrun() {
    local group="${1:?Usage: jrun <group> <cmd...> (groups: experiments, agents)}"
    shift
    if [[ "$group" != "experiments" && "$group" != "agents" ]]; then
      echo "Unknown group: $group (expected: experiments, agents)" >&2; return 1
    fi
    if ! pueue status &>/dev/null; then
      echo "pueued not running. Start with: systemctl --user start pueued" >&2; return 1
    fi
    if ! systemctl --user is-system-running &>/dev/null 2>&1; then
      echo "ERROR: systemd --user not available — cannot enforce resource limits" >&2
      echo "  Jobs would run without CPU/memory caps. Aborting." >&2
      echo "  Fix: loginctl enable-linger $(whoami)" >&2
      return 1
    fi
    # Set thread caps for experiments to prevent oversubscription
    local env_args=()
    if [[ "$group" == "experiments" ]]; then
      local threads="${EXPERIMENTS_THREADS:-2}"
      env_args=(env
        OMP_NUM_THREADS="$threads"
        MKL_NUM_THREADS="$threads"
        OPENBLAS_NUM_THREADS="$threads"
        NUMEXPR_NUM_THREADS="$threads"
        RAYON_NUM_THREADS="$threads"
        TOKENIZERS_PARALLELISM=false)
    fi
    pueue add --group "$group" --label "$(basename "$1")" -- \
      systemd-run --user --service-type=exec --wait --collect --slice="${group}.slice" \
        --setenv=PATH="$PATH" \
        --setenv=HOME="$HOME" \
        -- "${env_args[@]}" "$@"
  }

  # Shortcuts
  jexp() { jrun experiments "$@"; }
  jagent() { jrun agents "$@"; }
  jclaude() { jrun agents claude --print "$@"; }

  # Status
  alias jls='pueue status'
  alias jlog='pueue log'
  alias jfollow='pueue follow'
  alias jclean='pueue clean'
  alias jwatch='watch -n2 pueue status'

  # Control
  _jctl() {
    local action="$1" group="${2:?Usage: j${1} <group|all>}"
    [[ "$group" == "all" ]] && pueue "$action" || pueue "$action" --group "$group"
  }
  jpause()  { _jctl pause "$@"; }
  jresume() { _jctl start "$@"; }
  alias jkill='pueue kill'

  # Overview with resource usage
  jtop() {
    pueue status
    echo ""
    systemctl --user status experiments.slice agents.slice 2>/dev/null \
      || echo "(systemd slices not available)"
  }

fi

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

  export CLAUDE_CODE_TASK_LIST_ID="$task_list_id"
  claude
}

# Resume last task list in current directory
claude-last() {
  if [ -f .claude_task_list_id ]; then
    # shellcheck disable=SC1091
    source .claude_task_list_id
    echo "Resuming task list: $CLAUDE_CODE_TASK_LIST_ID"
    claude
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

  export CLAUDE_CODE_TASK_LIST_ID="$task_list_id"
  echo "Using task list: $task_list_id"
  claude
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

# zerobrew: faster Homebrew client (use zb for interactive installs, brew for scripts)
if command -v zb &>/dev/null; then
    alias zbi='zb install'
    alias zbu='zb uninstall'
fi

# Auto-agent guard controls
alias auto-guard='auto-agent-guardctl status'
alias auto-approve='auto-agent-guardctl approve'
alias auto-disable='auto-agent-guardctl disable'
alias auto-enable='auto-agent-guardctl enable'
alias auto-trace='auto-agent-guardctl trace'

# Clean duplicate skills from Claude Code (plugin symlinks cause 2x entries)
alias clean-skill-dupes='"$DOT_DIR/scripts/cleanup/clean_plugin_symlinks.sh"'

alias fda='fd -HI'  # fd all (include hidden + gitignored)

#-------------------------------------------------------------
# System utilities
#-------------------------------------------------------------

# Flush DNS cache
if [[ "$(uname)" == "Darwin" ]]; then
    alias flush='dscacheutil -flushcache && killall -HUP mDNSResponder'
    alias afk='pmset displaysleepnow'
else
    alias flush='sudo resolvectl flush-caches'
fi

# ISO week number
alias week='date +%V'

#-------------------------------------------------------------
# Ghostty themed windows
#-------------------------------------------------------------

# Launch Ghostty with a specific theme
# Uses window-save-state=never to prevent window restoration (single fresh window)
gtheme() {
    local theme=""
    local title=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -t|--title)
                title="${2:-}"
                shift 2
                ;;
            --title=*)
                title="${1#*=}"
                shift
                ;;
            -h|--help)
                echo "Usage: gtheme <theme-name> [title] [--title <title>]"
                echo "Example: gtheme 'Catppuccin Mocha' 'Docs'"
                echo "Example: gtheme 'Catppuccin Mocha' --title 'Docs'"
                echo ""
                echo "List themes: ghostty +list-themes"
                return 0
                ;;
            *)
                if [[ -z "$theme" ]]; then
                    theme="$1"
                elif [[ -z "$title" ]]; then
                    title="$1"
                else
                    echo "Error: unexpected argument '$1'"
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$theme" ]]; then
        echo "Usage: gtheme <theme-name> [title] [--title <title>]"
        echo "Example: gtheme 'Catppuccin Mocha' 'Docs'"
        echo "Example: gtheme 'Catppuccin Mocha' --title 'Docs'"
        echo ""
        echo "List themes: ghostty +list-themes"
        return 1
    fi

    if [[ "$OSTYPE" == darwin* ]]; then
        # macOS: use open, disable window restoration for fresh single window
        if [[ -n "$title" ]]; then
            open -na Ghostty --args --window-save-state=never --theme="$theme" --title="$title"
        else
            open -na Ghostty --args --window-save-state=never --theme="$theme"
        fi
    else
        # Linux: launch directly
        if [[ -n "$title" ]]; then
            ghostty --window-save-state=never --theme="$theme" --title="$title" &
        else
            ghostty --window-save-state=never --theme="$theme" &
        fi
        disown
    fi
}

# Quick theme aliases - 10 dark themes, diverse backgrounds + cursors
# Default (ghostty.conf): Catppuccin Mocha — pastel purple-blue, pink cursor
# Run `ghostty +list-themes` for full list, or `gtheme <name>` for any theme
g0() { gtheme "TokyoNight" --title "${1:+$1 | }🌙 [g0] TokyoNight"; }             # Deep blue bg, blue cursor — neon city
g1() { gtheme "Dracula" --title "${1:+$1 | }🧛 [g1] Dracula"; }                 # Purple-grey bg, white cursor — vibrant classic
g2() { gtheme "Nord" --title "${1:+$1 | }❄️ [g2] Nord"; }                        # Arctic blue-grey bg, white cursor — calm
g3() { gtheme "Rose Pine" --title "${1:+$1 | }🌹 [g3] Rose Pine"; }              # Deep purple bg, lavender cursor — botanical
g4() { gtheme "Kanagawa Dragon" --title "${1:+$1 | }🐉 [g4] Kanagawa Dragon"; }  # Warm near-black bg, warm cursor — Japanese ink
g5() { gtheme "Gruvbox Dark" --title "${1:+$1 | }🍂 [g5] Gruvbox Dark"; }        # Neutral warm bg, cream cursor — retro
g6() { gtheme "Everforest Dark Hard" --title "${1:+$1 | }🌲 [g6] Everforest"; }   # Green-grey bg, orange cursor — forest
g7() { gtheme "Solarized Dark Higher Contrast" --title "${1:+$1 | }☀️ [g7] Solarized"; } # Dark teal bg, red-orange cursor
g8() { gtheme "Melange Dark" --title "${1:+$1 | }🪨 [g8] Melange Dark"; }         # Warm brown bg, parchment cursor — earthy
g9() { gtheme "Material Ocean" --title "${1:+$1 | }🌊 [g9] Material Ocean"; }     # Near-black bg, yellow cursor — minimal

# Fix corrupted terminal state (preserves scrollback, unlike `reset`)
alias fix-term='_reset_terminal_modes'

# VPN split tunneling
alias vpn-status='tailscale-route-fix status'
alias vpn-fix='sudo tailscale-route-fix once'

# Supply chain: manual dependency audit
alias dep-audit='"$DOT_DIR/scripts/security/audit_dependencies.sh"'

# Supply chain defense: 7-day quarantine for uv (exclude-newer needs absolute date)
export UV_EXCLUDE_NEWER="$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

# Supply chain defense: socket wraps npm/npx with security scanning
if command -v socket &>/dev/null; then
    alias npm="socket npm"
    alias npx="socket npx"
fi

# SSH wrapper: nudge towards et/mosh for interactive sessions
# Neither is a drop-in replacement (different ports, tunnel syntax, no -i/-L/-D flags),
# so we only nudge when it looks like a plain interactive connection.
ssh() {
    if [[ -t 1 && $# -ge 1 ]]; then
        # Check for flags that indicate non-interactive use (forwarding, proxy, etc.)
        local interactive=true
        local arg
        for arg in "$@"; do
            case "$arg" in
                -N|-W|-L|-D|-R|-f|-G) interactive=false; break ;;
                -[A-Za-z]*[NWLDRF]*) interactive=false; break ;;  # combined flags like -fNL
            esac
        done
        if $interactive; then
            local host="${@: -1}"
            local alts=()
            command -v mosh &>/dev/null && alts+=("mosh $host")
            command -v et &>/dev/null && alts+=("et $host")
            if [[ ${#alts[@]} -gt 0 ]]; then
                local IFS=', '
                printf '\033[33m⚠ Persistent session? %s\033[0m\n' "${alts[*]}" >&2
            fi
        fi
    fi
    command ssh "$@"
}

# SSH theme switching moved to config/ssh_themes.sh (sourced by zshrc.sh)
