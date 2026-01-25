#!/usr/bin/env zsh
# SSH key auto-add (macOS Keychain / Linux ssh-agent)
# Automatically adds SSH keys to the agent on shell startup
# Safe: Never overwrites existing keys, prompts before generating new ones

# Only run in interactive shells
case "$-" in
  *i*) ;;
  *) return 0 2>/dev/null || exit 0 ;;
esac

# Default key path (can be overridden via SSH_KEY_PATH environment variable)
SSH_KEY="${SSH_KEY_PATH:-${HOME}/.ssh/id_ed25519}"

# Ensure ~/.ssh exists with safe perms
if [ ! -d "${HOME}/.ssh" ]; then
  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"
fi

# If the key is missing, offer to create it
if [ ! -f "${SSH_KEY}" ]; then
  echo "No SSH key found at ${SSH_KEY}."
  printf "Generate a new ed25519 SSH key now? [y/N] "
  read -r reply
  case "$reply" in
    y|Y|yes|YES)
      # Generate key with hostname as comment (helps identify which machine it's from)
      ssh-keygen -t ed25519 -f "${SSH_KEY}" -C "$(whoami)@$(hostname)" || return 0
      chmod 600 "${SSH_KEY}"
      echo "✓ SSH key generated at ${SSH_KEY}"
      echo "  Add to GitHub/GitLab: pbcopy < ${SSH_KEY}.pub (macOS) or cat ${SSH_KEY}.pub"
      ;;
    *)
      # Don't do anything further if there's no key
      return 0 2>/dev/null || exit 0
      ;;
  esac
fi

# Linux: Ensure ssh-agent is running
if [[ "$(uname -s)" == "Linux" ]]; then
  if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    eval "$(ssh-agent -s)" > /dev/null
  fi
fi

# If agent already has this identity loaded, do nothing
ssh-add -l 2>/dev/null | grep -q "${SSH_KEY}" && return 0 2>/dev/null || true

# Add the key (OS-specific behavior)
case "$(uname -s)" in
  Darwin)
    # macOS: Use Keychain to persist across sessions
    ssh-add --apple-use-keychain "${SSH_KEY}" >/dev/null 2>&1
    ;;
  Linux)
    # Linux: Add to ssh-agent (may require passphrase if key is encrypted)
    ssh-add "${SSH_KEY}" >/dev/null 2>&1
    ;;
esac
