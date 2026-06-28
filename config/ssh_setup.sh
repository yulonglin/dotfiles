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

# If the key is missing, warn and provide instructions
if [ ! -f "${SSH_KEY}" ]; then
  echo "⚠ No SSH key found at ${SSH_KEY}"
  echo "  To generate: ssh-keygen -t ed25519 -f ${SSH_KEY} -C \"\$(whoami)@\$(hostname)\""
  echo "  Then add to GitHub/GitLab: cat ${SSH_KEY}.pub"
  return 0 2>/dev/null || exit 0
fi

# Linux: Ensure ssh-agent is running
if [[ "$(uname -s)" == "Linux" ]]; then
  if ! pgrep -u "$USER" ssh-agent > /dev/null; then
    eval "$(ssh-agent -s)" > /dev/null
  fi
fi

# If the agent already has this identity loaded, do nothing.
# NOTE: `ssh-add -l` prints fingerprints, not file paths, so we must compare
# against the key's fingerprint (derived from the .pub file). Grepping for the
# path never matched, so ssh-add re-ran on every shell.
key_fp="$(ssh-keygen -lf "${SSH_KEY}.pub" 2>/dev/null | awk '{print $2}')"
key_loaded() { [ -n "${key_fp}" ] && ssh-add -l 2>/dev/null | grep -q "${key_fp}"; }
key_loaded && return 0 2>/dev/null || true

# Add the key (OS-specific behavior).
# `</dev/null` is critical: a startup script must never block an interactive
# shell on a passphrase prompt. If the passphrase isn't already in the Keychain,
# ssh-add fails silently instead of prompting on every new terminal.
case "$(uname -s)" in
  Darwin)
    # macOS: first load any passphrase already saved in the login Keychain
    # (silent). Only if that didn't load the key do we attempt a storing add.
    ssh-add --apple-load-keychain >/dev/null 2>&1 </dev/null
    if ! key_loaded; then
      ssh-add --apple-use-keychain "${SSH_KEY}" >/dev/null 2>&1 </dev/null
    fi
    ;;
  Linux)
    # Linux: add to ssh-agent. Encrypted keys without an agent-cached passphrase
    # are skipped silently rather than prompting on every shell.
    ssh-add "${SSH_KEY}" >/dev/null 2>&1 </dev/null
    ;;
esac
