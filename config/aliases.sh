# -------------------------------------------------------------------
# Source additional alias files
# -------------------------------------------------------------------
if [ -f "$DOT_DIR/config/aliases_inspect.sh" ]; then
    source "$DOT_DIR/config/aliases_inspect.sh"
fi

# -------------------------------------------------------------------
# personal
# -------------------------------------------------------------------

alias cdg="cd ~/git"
alias zrc="cd $DOT_DIR/zsh"
alias dot="cd $DOT_DIR"
alias jp="jupyter lab"
alias hn="hostname"
claude() {
    # Activate environment before running claude
    if [ -d ".venv" ] && [ -f ".venv/bin/activate" ]; then
        # shellcheck disable=SC1091
        source .venv/bin/activate
    fi
    command claude "$@"
}
alias yolo='claude --dangerously-skip-permissions'

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

# Auto-activate venv when cd'ing into a directory with one
cd() {
    builtin cd "$@" || return
    # Check for venv and activate if found (and not already in a venv from this dir)
    if [ -f ".venv/bin/activate" ]; then
        # shellcheck disable=SC1091
        source .venv/bin/activate
    elif [ -f "venv/bin/activate" ]; then
        # shellcheck disable=SC1091
        source venv/bin/activate
    fi
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
alias tree='tree -Csu'    # nice alternative to 'recursive ls'

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

# Update all AI CLI tools (platform-specific)
if [[ "$(uname -s)" == "Darwin" ]] && command -v brew &>/dev/null; then
    # macOS: Use Homebrew
    alias ai-update='brew upgrade --cask claude-code && brew upgrade gemini-cli codex'
elif command -v npm &>/dev/null; then
    # Linux or systems with npm
    alias ai-update='claude update && npm update -g @google/gemini-cli @openai/codex'
else
    alias ai-update='echo "Error: No package manager found for AI tools updates"'
fi

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
