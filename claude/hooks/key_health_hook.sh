#!/usr/bin/env zsh
# SessionStart: probe API keys in the BWS KEY_PRIORITY order (custom_bins/key-health).
# Announces any fallback, alerts loudly on revoked or missing keys, and points the
# model-router's OpenRouter key at the chosen key. Fails open: never blocks a session.
SCRIPT_PATH=${${(%):-%x}:A}
DOT_DIR=${SCRIPT_PATH:h:h:h}
for d in "$HOME/.local/bin" /opt/homebrew/bin /usr/local/bin "$DOT_DIR/custom_bins"; do
  [[ -d $d && ":$PATH:" != *":$d:"* ]] && PATH="$d:$PATH"
done
export PATH
[[ -x $DOT_DIR/custom_bins/key-health ]] || exit 0
exec "$DOT_DIR/custom_bins/key-health" --hook
