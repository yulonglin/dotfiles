# aliases/tmux.sh — tmux session aliases and chmod helpers

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
