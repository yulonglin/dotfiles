#!/bin/bash
# Script to clean up problematic zsh activation from .bashrc
# This removes the auto-exec zsh code that causes issues with Warp terminal

echo "Cleaning up .bashrc from problematic zsh activation..."

# Backup current .bashrc
if [ -f ~/.bashrc ]; then
    cp ~/.bashrc ~/.bashrc.backup.$(date +%Y%m%d_%H%M%S)
    echo "Backed up current .bashrc"
fi

# Remove the problematic zsh activation block
if [ -f ~/.bashrc ]; then
    # Create temp file without the problematic block
    awk '
    /# Use local zsh if available/ {
        in_block = 1
    }
    in_block && /^fi$/ {
        in_block = 0
        next
    }
    !in_block {
        print
    }
    ' ~/.bashrc > ~/.bashrc.tmp
    
    # Replace the original file
    mv ~/.bashrc.tmp ~/.bashrc
    echo "Removed zsh auto-activation from .bashrc"
fi

echo "Cleanup complete!"
echo ""
echo "Next steps:"
echo "1. Run: ./deploy.sh  (to set up proper configuration)"
echo "2. Open a new terminal session to test"
echo ""
echo "Note: ZSH switching is now handled through .bash_profile to avoid Warp terminal issues."
echo "If you're using bash and want to switch to zsh, you can:"
echo "  - Type 'switch_to_zsh' if the function is available"
echo "  - Or manually run: exec zsh"