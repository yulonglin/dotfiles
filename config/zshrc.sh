CONFIG_DIR=$(dirname $(realpath ${(%):-%x}))
DOT_DIR=${CONFIG_DIR:h}

# User-customizable directory locations (override in ~/.zshenv or config/secrets.sh)
CODE_DIR="${CODE_DIR:-$HOME/code}"           # Primary code projects
WRITING_DIR="${WRITING_DIR:-$HOME/writing}"  # Writing projects (papers, notes)
SCRATCH_DIR="${SCRATCH_DIR:-$HOME/scratch}"  # Temporary experimentation
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/projects}"  # General projects

# Disable AUTO_CD - require explicit cd commands
unsetopt AUTO_CD

# Auto-attach tmux over SSH — survives disconnects, preserves scrollback
# Guards: interactive only, SSH only, not already in tmux, not a forced command,
#         tmux available, opt-out with NO_AUTO_TMUX=1
if [[ -o interactive && -n "$SSH_CONNECTION" && -z "$TMUX" && -z "$NO_AUTO_TMUX" ]] \
   && command -v tmux &>/dev/null; then
  _tmux_sessions=$(tmux list-sessions 2>/dev/null)
  _tmux_count=$(echo "$_tmux_sessions" | grep -c '^' 2>/dev/null || echo 0)
  if [[ $_tmux_count -eq 0 ]]; then
    # No sessions — create one
    exec tmux new-session -s main
  elif [[ $_tmux_count -eq 1 ]]; then
    # One session — attach it
    _tmux_name=${_tmux_sessions%%:*}
    exec tmux attach -t "$_tmux_name"
  else
    # Multiple sessions — show picker, let user choose
    echo "tmux sessions:"
    echo "$_tmux_sessions"
    echo ""
    echo "  ta        attach last    taa <name>  attach named"
    echo "  tn <name> new session    NO_AUTO_TMUX=1 ssh ...  skip"
  fi
  unset _tmux_sessions _tmux_count _tmux_name
fi

# Instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
export TERM="xterm-256color"
export COLORTERM="truecolor"

# Editor — reads from macos_default_apps.conf (single source of truth)
_fa_conf="$DOT_DIR/config/macos_default_apps.conf"
if [[ -f "$_fa_conf" ]]; then
  # Source only the EDITOR_CLI* variables (fast, no array eval)
  EDITOR_CLI=$(sed -n 's/^EDITOR_CLI="\(.*\)"/\1/p' "$_fa_conf" | head -1)
  EDITOR_CLI_SSH=$(sed -n 's/^EDITOR_CLI_SSH="\(.*\)"/\1/p' "$_fa_conf" | head -1)
fi
if [[ -n $SSH_CONNECTION ]]; then
  export EDITOR="${EDITOR_CLI_SSH:-edit}"
else
  export EDITOR="${EDITOR_CLI:-cursor --wait}"
fi
export VISUAL="$EDITOR"
unset _fa_conf EDITOR_CLI EDITOR_CLI_SSH

# Claude Code tmpdir - avoid root-owned /tmp/claude issues
if [[ -n "$TMPDIR" && -w "$TMPDIR" ]]; then
    # Explicit TMPDIR takes priority (cloud environments, user preference)
    export CLAUDE_CODE_TMPDIR="$TMPDIR/claude"
elif [[ -d "/run/user/$(id -u)" && -w "/run/user/$(id -u)" ]]; then
    # Linux: XDG runtime dir (per-user tmpfs, mode 0700)
    export CLAUDE_CODE_TMPDIR="/run/user/$(id -u)/claude"
else
    # Fallback: home dir (always writable, survives reboots)
    export CLAUDE_CODE_TMPDIR="$HOME/tmp/claude"
fi

# RunPod/container: allow Claude Code bypass-permissions as root
if [[ "$(id -u)" == "0" ]] && { [[ -n "$RUNPOD_POD_ID" ]] || [[ -d /workspace ]]; }; then
    export IS_SANDBOX=1
fi

ZSH_DISABLE_COMPFIX=true
ZSH_THEME="powerlevel10k/powerlevel10k"
ZSH=$HOME/.oh-my-zsh

plugins=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions zsh-history-substring-search zsh-shift-select)

if [ -f "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
fi
source $CONFIG_DIR/aliases.sh
[ -f $CONFIG_DIR/secrets.sh ] && source $CONFIG_DIR/secrets.sh
if [ -x "$DOT_DIR/custom_bins/dotfiles-secrets" ]; then
  # Ad-hoc least-privilege helper for one-off commands.
  # Usage: with-secrets KEY1 [KEY2 ...] -- command [args...]
  with-secrets() {
    local args=("$@")
    local keys=()
    local saw_separator=false
    local i

    [[ $# -gt 0 ]] || { echo "Usage: with-secrets KEY1 [KEY2 ...] -- command [args...]" >&2; return 1; }

    for ((i = 1; i <= $#; i++)); do
      if [[ "${args[i]}" == "--" ]]; then
        saw_separator=true
        break
      fi
      keys+=("${args[i]}")
    done

    [[ "$saw_separator" == true ]] || { echo "Usage: with-secrets KEY1 [KEY2 ...] -- command [args...]" >&2; return 1; }
    [[ ${#keys[@]} -gt 0 ]] || { echo "Provide at least one key or use --all before --" >&2; return 1; }
    shift $(( ${#keys[@]} + 1 ))
    [[ $# -gt 0 ]] || { echo "Provide a command after --" >&2; return 1; }

    (
      if [[ "${keys[1]}" == "--all" ]]; then
        source <("$DOT_DIR/custom_bins/dotfiles-secrets" shell --all)
      else
        source <("$DOT_DIR/custom_bins/dotfiles-secrets" shell "${keys[@]}")
      fi
      "$@"
    )
  }
fi
source $CONFIG_DIR/ssh_setup.sh
source $CONFIG_DIR/p10k.zsh
source $CONFIG_DIR/extras.sh
source $CONFIG_DIR/modern_tools.sh
source $CONFIG_DIR/key_bindings.sh
source $CONFIG_DIR/ssh_themes.sh
source $CONFIG_DIR/completions.sh
add_to_path "${DOT_DIR}/custom_bins"

# Machine auto-registration: prompt once on unregistered machines (interactive shells only)
if [[ -o interactive && ! -f "${HOME}/.cache/machine-register-prompted" ]]; then
  _machine_registry="${DOT_DIR}/config/machines.conf"
  _machine_id=""
  if [[ -f /etc/machine-id ]]; then
    _machine_id=$(cat /etc/machine-id)
  elif command -v ioreg >/dev/null 2>&1; then
    _machine_id=$(ioreg -rd1 -c IOPlatformExpertDevice 2>/dev/null | awk -F'"' '/IOPlatformUUID/{print $4}' | tr '[:upper:]' '[:lower:]')
  fi
  if [[ -n "$_machine_id" && -f "$_machine_registry" ]] && ! grep -q "^${_machine_id}|" "$_machine_registry" 2>/dev/null; then
    printf '\n🆕 Unregistered machine detected (hostname: %s)\n' "${HOST:-$(hostname -s)}"
    printf '   Run \033[1mmachine-register\033[0m to name this machine for prompt/statusline display.\n\n'
    mkdir -p "${HOME}/.cache"
    touch "${HOME}/.cache/machine-register-prompted"
  fi
  unset _machine_registry _machine_id
fi

# Add ~/.local/bin to PATH (for Claude Code, gh, gitleaks, uv tools)
add_to_path "$HOME/.local/bin"

# bun - fast JavaScript runtime and package manager (preferred on Linux)
[[ -d "$HOME/.bun/bin" ]] && add_to_path "$HOME/.bun/bin"

# npm global packages - avoid permission issues with /usr/lib/node_modules
# Installs to ~/.npm-global instead of requiring sudo
if command -v npm &>/dev/null; then
  export NPM_CONFIG_PREFIX="$HOME/.npm-global"
  add_to_path "$HOME/.npm-global/bin"
fi

# Add plotting library to PYTHONPATH (anthro_colors, petriplot)
if [[ -d "$HOME/.local/lib/plotting" ]]; then
    export PYTHONPATH="$HOME/.local/lib/plotting:${PYTHONPATH}"
fi

# LS_COLORS — use vivid with catppuccin-mocha theme (matches Ghostty terminal theme)
# Fixes unreadable directory colors (default ow=34;42 is blue-on-green)
if command -v vivid &>/dev/null; then
    export LS_COLORS="$(vivid generate catppuccin-mocha)"
fi

# ripgrep config — skip git's global ignore (has research patterns), use universal-only ignore
[[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/config" ]] && \
    export RIPGREP_CONFIG_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/ripgrep/config"

# Source uv environment if installed
[ -f "$HOME/.local/bin/env" ] && source "$HOME/.local/bin/env"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
if [ -d "$HOME/.cargo" ]; then
  . "$HOME/.cargo/env"
fi

# mise - universal version manager (replaces pyenv, nvm, rbenv, etc.)
# Installed by default on Linux, manages CLI tools and language runtimes
if command -v mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi

# zoxide (smarter cd - use 'z' command, not replacing cd)
# Note: If installed via mise, it's already in PATH after mise activate
command -v zoxide &> /dev/null && eval "$(zoxide init zsh)"

# direnv — auto-load .envrc per-directory (SOPS secrets, env vars)
command -v direnv &>/dev/null && eval "$(direnv hook zsh)"

# Legacy version managers (used if mise is not available)
if [ -d "$HOME/.pyenv" ] && ! command -v mise &>/dev/null; then
  export PYENV_ROOT="$HOME/.pyenv"
  command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
fi

if [ -d "$HOME/.local/bin/micromamba" ]; then
  export MAMBA_EXE="$HOME/.local/bin/micromamba"
  export MAMBA_ROOT_PREFIX="$HOME/micromamba"
  __mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
  if [ $? -eq 0 ]; then
      eval "$__mamba_setup"
  else
      alias micromamba="$MAMBA_EXE"  # Fallback on help from mamba activate
  fi
  unset __mamba_setup
fi

# fnm (fast node manager) - legacy, prefer mise for Node.js management
FNM_PATH="$HOME/.local/share/fnm"
if [ -d "$FNM_PATH" ] && ! command -v mise &>/dev/null; then
  export PATH="$FNM_PATH:$PATH"
  eval "`fnm env`"
fi

if command -v ask-sh &> /dev/null; then
  ASK_SH_OPENAI_API_KEY=$(cat $HOME/.openai_api_key 2>/dev/null)
  ASK_SH_OPENAI_MODEL=gpt-4o-mini
  eval "$(ask-sh --init)"
fi

# Reset terminal modes that may be left enabled after ungraceful process exit
# (e.g., SSH disconnect while running mouse-enabled app like tmux/vim/htop)
# _reset_terminal_modes_soft: safe for precmd (no alt screen exit — that can wipe display)
# _reset_terminal_modes: full reset including alt screen, for manual fix-term / sshc
_reset_terminal_modes_soft() {
    [[ -t 1 ]] || return
    local reset=''
    reset+='\e[?1000l'  # mouse click tracking
    reset+='\e[?1002l'  # mouse button-event tracking
    reset+='\e[?1003l'  # mouse any-event tracking
    reset+='\e[?1006l'  # SGR mouse mode (the 35M sequences)
    reset+='\e[?1007l'  # alternate scroll mode (scroll → arrow keys)
    reset+='\e[?1004l'  # focus event reporting
    reset+='\e[?2004l'  # bracketed paste mode
    reset+='\e[?1l'     # application cursor keys
    reset+='\e[?66l'    # application keypad mode
    reset+='\e[?25h'    # cursor visible
    reset+='\e(B'       # ASCII charset
    printf "$reset"
}
_reset_terminal_modes() {
    _reset_terminal_modes_soft
    [[ -t 1 ]] && printf '\e[?1049l'  # exit alternate screen buffer
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _reset_terminal_modes_soft
# Exit alt screen once at shell startup (recovers scrollback after SSH disconnect;
# mid-session kill -9 of alt-screen apps needs manual fix-term)
_reset_terminal_modes

# Only display ASCII art in interactive shells
if [[ -o interactive ]]; then
  cat $CONFIG_DIR/start.txt
fi

fs() {
    # Check if user is asking for help
    if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
        find-session --help
        return
    fi
    # Run find-session in shell mode and evaluate the output
    eval "$(find-session --shell "$@" | sed '/^$/d')"
}

# Auto-activate .venv on shell startup (same as cd behavior)
activate_venv
