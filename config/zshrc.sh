CONFIG_DIR=$(dirname $(realpath ${(%):-%x}))
DOT_DIR=$CONFIG_DIR/..

# Instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
export TERM="xterm-256color"

ZSH_DISABLE_COMPFIX=true
ZSH_THEME="powerlevel10k/powerlevel10k"
ZSH=$HOME/.oh-my-zsh

plugins=(zsh-autosuggestions zsh-syntax-highlighting zsh-completions zsh-history-substring-search zsh-shift-select)

if [ -f "$ZSH/oh-my-zsh.sh" ]; then
  source "$ZSH/oh-my-zsh.sh"
fi
source $CONFIG_DIR/aliases.sh
source $CONFIG_DIR/p10k.zsh
source $CONFIG_DIR/extras.sh
source $CONFIG_DIR/modern_tools.sh
source $CONFIG_DIR/key_bindings.sh
source $CONFIG_DIR/completions.sh
add_to_path "${DOT_DIR}/custom_bins"

# for uv
if [ -d "$HOME/.local/bin" ]; then
  source $HOME/.local/bin/env
fi

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
  export ASK_SH_OPENAI_API_KEY=$(cat $HOME/.openai_api_key)
  export ASK_SH_OPENAI_MODEL=gpt-4o-mini
  eval "$(ask-sh --init)"
fi

# Only display ASCII art in interactive shells
if [[ -o interactive ]]; then
  cat $CONFIG_DIR/start.txt
fi

# Atuin - unified shell history
if [ -f "$HOME/.atuin/bin/env" ]; then
    source "$HOME/.atuin/bin/env"
    eval "$(atuin init zsh --disable-up-arrow)"
elif command -v atuin &> /dev/null; then
    eval "$(atuin init zsh --disable-up-arrow)"
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
_activate_venv
