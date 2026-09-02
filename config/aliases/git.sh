# aliases/git.sh — git aliases
#
# Pruned 2026-08-18: 41 → 14. Two months of history showed 4 in use (gl gpl gd gs);
# Claude Code does most terminal git. The oh-my-zsh long tail (grb*/gst*/gcp*/gsw*/
# gb*/gpo/gpsup/ggsup/gau/gaa/gm/gg/gdt/grv/gcm/gpf/grhard/grhead) was removed —
# type the git command, or re-add an alias here when one earns its place.

#-------------------------------------------------------------
# git
#-------------------------------------------------------------

alias g="git"
alias gcl="git clone"
alias ga="git add"
alias gc="git commit -m"
alias gp="git push"

alias glog='git log --oneline --all --graph --decorate'
alias gl="git log --oneline -20"

alias gf="git fetch"
alias gpl="git pull"

alias gd="git diff"
alias gds="git diff --staged"
alias gs="git status"

alias gco="git checkout"
alias gcb="git checkout -b"
