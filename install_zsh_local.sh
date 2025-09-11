#!/bin/bash

set -e

# Script to install ZSH locally without sudo access
# This installs ncurses and zsh to $HOME/local
# Based on: https://gist.github.com/ZhaofengWu/f345652e994e3b68c309352a7610460f

echo "Installing ZSH locally to $HOME/local..."

# Create local directory structure
mkdir -p $HOME/local/{bin,lib,include,share}

# Set up environment variables for compilation
export PREFIX=$HOME/local
export CXXFLAGS=" -fPIC" 
export CFLAGS=" -fPIC" 
export CPPFLAGS="-I${PREFIX}/include" 
export LDFLAGS="-L${PREFIX}/lib"
export PATH=$PREFIX/bin:$PATH
export LD_LIBRARY_PATH=$PREFIX/lib:$LD_LIBRARY_PATH

# Install ncurses (required for zsh)
echo "Installing ncurses..."
# Get latest ncurses version
NCURSES_VERSION=$(curl -s https://ftp.gnu.org/pub/gnu/ncurses/ | grep -oP 'ncurses-\K[0-9.]+(?=\.tar\.gz)' | sort -V | tail -1)
echo "Found ncurses version: $NCURSES_VERSION"
wget https://ftp.gnu.org/pub/gnu/ncurses/ncurses-${NCURSES_VERSION}.tar.gz
tar -xzf ncurses-${NCURSES_VERSION}.tar.gz
cd ncurses-${NCURSES_VERSION}
./configure --prefix=$PREFIX --enable-shared --with-shared --enable-pc-files --with-pkg-config-libdir=$PREFIX/lib/pkgconfig
make -j$(nproc)
make install
cd ..
rm -rf ncurses-${NCURSES_VERSION}.tar.gz ncurses-${NCURSES_VERSION}

# Install zsh (using latest from sourceforge)
echo "Downloading latest ZSH..."
wget -O zsh-latest.tar.xz https://sourceforge.net/projects/zsh/files/latest/download
mkdir zsh-build && tar -xf zsh-latest.tar.xz -C zsh-build --strip-components=1
cd zsh-build
echo "Installing ZSH version: $(cat Config/version.mk | grep 'VERSION =' | cut -d' ' -f3)"
./configure --prefix=$PREFIX --enable-multibyte --enable-function-subdirs --with-tcsetpgrp
make -j$(nproc)
make install
cd ..
rm -rf zsh-latest.tar.xz zsh-build

# Create activation script
cat > $HOME/local/activate_zsh.sh << 'EOF'
# Source this file to use local zsh installation
export PATH=$HOME/local/bin:$PATH
export LD_LIBRARY_PATH=$HOME/local/lib:$LD_LIBRARY_PATH
export SHELL=$HOME/local/bin/zsh
export ZDOTDIR=$HOME
EOF

# Update bashrc to automatically use local zsh
if ! grep -q "local/activate_zsh.sh" ~/.bashrc 2>/dev/null; then
    cat >> ~/.bashrc << 'EOF'

# Use local zsh if available
if [ -f $HOME/local/activate_zsh.sh ] && [ -f $HOME/local/bin/zsh ]; then
    source $HOME/local/activate_zsh.sh
    # Auto-start zsh if not already in zsh and interactive shell
    if [ -z "$ZSH_VERSION" ] && [ -n "$PS1" ]; then
        HOME=$HOME ZDOTDIR=$HOME exec $HOME/local/bin/zsh -l
    fi
fi
EOF
fi

# Get the real HOME directory (in case we're in a temp directory like Warp creates)
REAL_HOME=$(eval echo ~$(whoami))

# Create a minimal .zshrc to prevent newuser prompt
if [ ! -f "$REAL_HOME/.zshrc" ]; then
    echo "Creating minimal .zshrc to prevent newuser prompt..."
    cat > $REAL_HOME/.zshrc << 'EOF'
# Minimal zshrc to prevent newuser install prompt
# This file will be replaced when oh-my-zsh is installed via install.sh

# Add local zsh to PATH
export PATH=$HOME/local/bin:$PATH
export LD_LIBRARY_PATH=$HOME/local/lib:$LD_LIBRARY_PATH

# Basic configuration
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
EOF
fi

# Create .zshenv to ensure ZDOTDIR points to the correct location (for Warp terminal)
if [ ! -f "$REAL_HOME/.zshenv" ]; then
    echo "Creating .zshenv to handle directory issues..."
    cat > $REAL_HOME/.zshenv << EOF
# Ensure ZDOTDIR points to the real home directory
export ZDOTDIR=\$HOME
EOF
fi

echo "ZSH installation complete!"
echo ""
echo "ZSH has been installed to $HOME/local/bin/zsh"
echo "Your ~/.bashrc has been updated to auto-start ZSH on login."
echo ""
echo "Next steps:"
echo "1. Run: source ~/.bashrc"
echo "2. Run: ./install.sh --force  (to install oh-my-zsh and plugins)"