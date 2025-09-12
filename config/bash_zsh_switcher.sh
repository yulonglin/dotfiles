#!/bin/bash
# Bash to ZSH switcher script
# This is sourced from .bash_profile instead of .bashrc to avoid issues with Warp terminal
# It provides a smooth transition to zsh when available

# Get the real home directory (handle Warp's temp directories)
REAL_HOME=$(eval echo ~$(whoami))

# Use local zsh if available
if [ -f $REAL_HOME/local/activate_zsh.sh ] && [ -f $REAL_HOME/local/bin/zsh ]; then
    # Fix PATH and LD_LIBRARY_PATH for local zsh
    export PATH=$REAL_HOME/local/bin:$PATH
    export LD_LIBRARY_PATH=$REAL_HOME/local/lib:$LD_LIBRARY_PATH
    
    # Provide a manual switch function for interactive shells
    if [ -z "$ZSH_VERSION" ] && [ -n "$PS1" ]; then
        echo "ZSH is available. Run 'switch_to_zsh' or 'zsh' to switch to ZSH"
        switch_to_zsh() {
            # Force HOME and ZDOTDIR to real home to avoid Warp temp directory issues
            HOME=$REAL_HOME ZDOTDIR=$REAL_HOME exec $REAL_HOME/local/bin/zsh -l
        }
        # Alias for convenience
        alias zsh="HOME=$REAL_HOME ZDOTDIR=$REAL_HOME $REAL_HOME/local/bin/zsh"
    fi
# Check for system zsh as fallback
elif command -v zsh &> /dev/null; then
    if [ -z "$ZSH_VERSION" ] && [ -n "$PS1" ]; then
        # Check if we're in a terminal that might have issues with exec
        if [ "$TERM_PROGRAM" != "WarpTerminal" ]; then
            exec zsh -l
        else
            # For Warp terminal, provide a manual switch function
            echo "ZSH is available. Run 'switch_to_zsh' to switch to ZSH"
            switch_to_zsh() {
                exec zsh -l
            }
        fi
    fi
fi