# aliases/nav.sh — directory navigation, cd with venv auto-activation, directory shortcuts

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
