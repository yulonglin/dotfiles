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

# Load the key (OS-specific). This script only ever *loads* an already-known
# passphrase — it must never run a *storing* add, because ssh-add reads
# passphrases from /dev/tty directly (bypassing stdin/stderr redirection), so an
# un-enrolled passphrase-protected key would prompt on EVERY new shell.
case "$(uname -s)" in
  Darwin)
    # macOS: load any passphrase already saved in the login Keychain (silent).
    # Enrolling a new key is a deliberate one-time step you run by hand:
    #   ssh-add --apple-use-keychain ~/.ssh/id_ed25519
    # After that, this load picks it up on every shell with no prompt.
    ssh-add --apple-load-keychain >/dev/null 2>&1 </dev/null
    ;;
  Linux)
    # Linux: add to ssh-agent. </dev/null avoids hanging a non-interactive
    # shell; passphrase-protected keys without an agent-cached passphrase are
    # left unloaded (ssh will prompt on first use) rather than prompting here.
    ssh-add "${SSH_KEY}" >/dev/null 2>&1 </dev/null
    ;;
esac
