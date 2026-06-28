#!/bin/bash
# Quick restore after container restart — delegates to create-user.sh
# RunPod containers lose /etc/passwd and /home on restart.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/restart.sh | bash
#   curl -fsSL ... | USERNAME=dev bash

USERNAME="${1:-${USERNAME:-yulong}}"
export USERNAME

BRANCH="https://raw.githubusercontent.com/yulonglin/dotfiles/main/scripts/cloud/create-user.sh"
curl -fsSL "$BRANCH" | bash

echo ""
echo "Switch: su - $USERNAME"
