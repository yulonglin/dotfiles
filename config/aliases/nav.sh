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

alias ..='cd ..'
alias ...='cd ../../'
alias ....='cd ../../../'

alias dotfiles='cd $CODE_DIR/dotfiles'
alias code='cd $CODE_DIR'
alias writing='cd $WRITING_DIR'
alias scratch='cd $SCRATCH_DIR'
alias projects='cd $PROJECTS_DIR'
alias website='cd $WRITING_DIR/${DOTFILES_WEBSITE:-yulonglin.github.io}'
alias vault='cd $VAULT_DIR'
