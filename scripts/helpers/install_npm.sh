#!/usr/bin/env bash

# Programmatically fetch the latest NVM release version from GitHub
NVM_VERSION="$(curl -s https://api.github.com/repos/nvm-sh/nvm/releases/latest | grep -oP '"tag_name":\s*"\K(.*)(?=")')"

if [ -z "$NVM_VERSION" ]; then
  echo "❌ Failed to fetch latest NVM version. Falling back to v0.40.3"
  NVM_VERSION="v0.40.3"
fi

echo "Installing NVM version: $NVM_VERSION"

# Install NVM ($NVM_VERSION)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh | bash

# Load NVM into the current shell session
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# (Optional) Load NVM bash_completion for tab-completion
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Install the latest Node.js (includes npm)
nvm install node

# Set default Node.js version for all new shells
nvm alias default node

echo "✅ NVM $NVM_VERSION and latest Node.js installed successfully."
echo "   Restart your terminal or run the following to use nvm now:"
echo "   export NVM_DIR=\"\$HOME/.nvm\" && [ -s \"\$NVM_DIR/nvm.sh\" ] && \\. \"\$NVM_DIR/nvm.sh\""
