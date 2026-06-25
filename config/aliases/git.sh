# aliases/git.sh — git aliases

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
