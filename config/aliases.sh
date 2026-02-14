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
alias sync-secrets='"$DOT_DIR/scripts/sync_secrets.sh"'

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

    # Auto-cd to git root so plansDirectory: ".claude/plans" resolves correctly
    # Must happen before task ID generation so auto-name reflects git root, not subdir
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -n "$git_root" && "$PWD" != "$git_root" ]]; then
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

    activate_venv
    command claude "${args[@]}"
}
alias yolo='claude --dangerously-skip-permissions'
alias resume='yolo --resume'
alias cont='yolo --continue'
alias continue='yolo --continue'
alias yn='yolo -t'  # yn <name>: yolo with task name

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
alias website='cd $WRITING_DIR/yulonglin.github.io'

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
alias gpf="git push -f"
alias gpo='git push origin $(git_current_branch)'
alias gpp='git push --set-upstream origin $(git_current_branch)'

alias gg='git gui'
alias glog='git log --oneline --all --graph --decorate'

alias gf="git fetch"
alias gl="git pull"

alias grb="git rebase"
alias grbm="git rebase master"
alias grbc="git rebase --continue"
alias grbs="git rebase --skip"
alias grba="git rebase --abort"

alias gd="git diff"
alias gdt="git difftool"
alias gs="git status"

alias gco="git checkout"
alias gcb="git checkout -b"
alias gcm="git checkout master"

alias grhead="git reset HEAD^"
alias grhard="git fetch origin && git reset --hard"

alias gst="git stash"
alias gstp="git stash pop"
alias gsta="git stash apply"
alias gstd="git stash drop"
alias gstc="git stash clear"

alias ggsup='git branch --set-upstream-to=origin/$(git_current_branch)'
alias gpsup='git push --set-upstream origin $(git_current_branch)'

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

#-------------------------------------------------------------
# ls
#-------------------------------------------------------------

alias l="ls -CF --color=auto"
alias ll="ls -l --group-directories-first"
alias la='ls -Al'         # show hidden files
alias lx='ls -lXB'        # sort by extension
alias lk='ls -lSr'        # sort by size, biggest last
alias lc='ls -ltcr'       # sort by and show change time, most recent last
alias lu='ls -ltur'       # sort by and show access time, most recent last
alias lt='ls -ltr'        # sort by date, most recent last
alias lm='ls -al |more'   # pipe through 'more'
alias lr='ls -lR'         # recursive ls
# tree using eza (better git integration, colors)
alias tree='eza --tree --icons --git-ignore'
alias t1='eza --tree --level=1'
alias t2='eza --tree --level=2'
alias t3='eza --tree --level=3'

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

# Clear Claude Code processes
alias ccl='clear-claude-code --list'          # list/status
alias cc-list='clear-claude-code --list'
alias ccp='clear-claude-code --preview'       # preview/dry-run
alias cc-preview='clear-claude-code --preview'
alias cci='clear-claude-code'                 # kill idle only (safe)
alias cc-idle='clear-claude-code'
alias ccf='clear-claude-code --force'         # kill all except current (confirms)
alias cc-force='clear-claude-code --force'
alias cca='clear-claude-code --all'           # kill everything (confirms)
alias cc-all='clear-claude-code --all'

# Update all AI CLI tools (delegates to update-ai-tools script)
alias ai-update='update-ai-tools'

# System package update + upgrade + cleanup (delegates to update-packages script)
# Detects: brew (macOS), apt/dnf/pacman (Linux)
alias pkg-update='update-packages'

# Clean duplicate skills from Claude Code (plugin symlinks cause 2x entries)
alias clean-skill-dupes='"$DOT_DIR/scripts/cleanup/clean_plugin_symlinks.sh"'

# # -------------------------------------------------------------------
# # Better utils: https://www.lesswrong.com/posts/6P8GYb4AjtPXx6LLB/tips-and-code-for-empirical-research-workflows
# # -------------------------------------------------------------------
# alias grep='rg'    # use ripgrep as grep
# alias du='dust'    # use dust as du
# alias df='duf'     # use duf as df
# # alias cat='bat'    # use bat as cat (commenting this out since the lines in bat can be annoying for parsing and copying)
# alias find='fd'    # use fd as find
# alias ls='eza'     # use eza as ls


alias fda='fd -HI'  # fd all (include hidden + gitignored)

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

# Quick theme aliases - visually distinct, good readability, popular
# Run `ghostty +list-themes` for full list, or `gtheme <name>` for any theme
alias g1='gtheme "Catppuccin Mocha"'      # Pastel dark, lavender/pink
alias g2='gtheme "TokyoNight"'            # Cool dark, deep blue/purple
alias g3='gtheme "Gruvbox Dark"'          # Retro warm, orange/brown earth
alias g4='gtheme "Kanagawa Dragon"'       # Muted ink, dark slate/jade
alias g5='gtheme "Everforest Dark Hard"'  # Forest green, olive/sage
alias g6='gtheme "Solarized Dark Higher Contrast"' # Teal-gray, classic readable

#-------------------------------------------------------------
# SSH with terminal color changes
#-------------------------------------------------------------
# Changes terminal colors when SSH-ing to help identify which machine you're on
# Colors revert when SSH session ends

# Color schemes for SSH hosts (bg, fg, cursor)
# Format: "background:foreground:cursor" in hex
typeset -A SSH_HOST_COLORS
# Add your hosts here - pattern matching supported
# SSH_HOST_COLORS[prod*]="#3d0000:#ffffff:#ff6666"      # Red-tinted for production
# SSH_HOST_COLORS[dev*]="#002200:#ffffff:#66ff66"       # Green-tinted for dev
# SSH_HOST_COLORS[staging*]="#1a1a00:#ffffff:#ffff66"   # Yellow-tinted for staging
# SSH_HOST_COLORS[gpu*]="#1a0033:#ffffff:#cc66ff"       # Purple for GPU servers
SSH_HOST_COLORS[default]="#0d1926:#c5d4dd:#88c0d0"     # Blue-gray default for any SSH

# Save current terminal colors (for restoration)
_ssh_save_colors() {
    # Query current colors via OSC - not all terminals support this
    # Fall back to sensible defaults
    export _SSH_ORIG_BG="${_SSH_ORIG_BG:-#1e1e2e}"
    export _SSH_ORIG_FG="${_SSH_ORIG_FG:-#cdd6f4}"
    export _SSH_ORIG_CURSOR="${_SSH_ORIG_CURSOR:-#f5e0dc}"
}

# Set terminal colors via OSC escape sequences
_ssh_set_colors() {
    local bg="$1" fg="$2" cursor="$3"
    [[ -n "$bg" ]] && printf '\e]11;%s\a' "$bg"
    [[ -n "$fg" ]] && printf '\e]10;%s\a' "$fg"
    [[ -n "$cursor" ]] && printf '\e]12;%s\a' "$cursor"
}

# Restore original terminal colors
_ssh_restore_colors() {
    _ssh_set_colors "$_SSH_ORIG_BG" "$_SSH_ORIG_FG" "$_SSH_ORIG_CURSOR"
    unset _SSH_ORIG_BG _SSH_ORIG_FG _SSH_ORIG_CURSOR
}

# Find color scheme for a host (supports wildcards)
_ssh_get_host_colors() {
    local host="$1"
    local colors=""

    # Check for matching pattern
    for pattern in "${(@k)SSH_HOST_COLORS}"; do
        if [[ "$pattern" != "default" && "$host" == $~pattern ]]; then
            colors="${SSH_HOST_COLORS[$pattern]}"
            break
        fi
    done

    # Fall back to default if no match
    [[ -z "$colors" ]] && colors="${SSH_HOST_COLORS[default]}"
    echo "$colors"
}

# SSH wrapper with color changing
# Usage: sshc hostname [ssh args...]
# Or add hosts to SSH_HOST_COLORS above and use regular ssh alias
sshc() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: sshc <host> [ssh args...]"
        echo ""
        echo "Configured hosts (edit SSH_HOST_COLORS in aliases.sh):"
        for pattern in "${(@k)SSH_HOST_COLORS}"; do
            echo "  $pattern"
        done
        return 1
    fi

    local host="$1"
    shift

    # Extract hostname from user@host format
    local hostname="${host#*@}"

    # Get colors for this host
    local colors
    colors=$(_ssh_get_host_colors "$hostname")

    if [[ -n "$colors" ]]; then
        _ssh_save_colors

        # Parse colors (bg:fg:cursor)
        local bg fg cursor
        IFS=':' read -r bg fg cursor <<< "$colors"
        _ssh_set_colors "$bg" "$fg" "$cursor"

        # Run SSH, restore colors on exit
        command ssh "$host" "$@"
        local exit_code=$?

        _ssh_restore_colors
        return $exit_code
    else
        # No color config, just run ssh normally
        command ssh "$host" "$@"
    fi
}

# Auto-use sshc in Ghostty (color-changing ssh)
if [[ "$TERM_PROGRAM" == "ghostty" ]]; then
    alias ssh='sshc'
fi
