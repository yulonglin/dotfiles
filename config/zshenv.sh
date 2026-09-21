#!/usr/bin/env zsh
# Sourced by EVERY zsh, including non-interactive and non-login ones.
#
# This exists for one reason: `mosh` starts its server by running `mosh-server`
# through a NON-interactive ssh shell. That shell reads only ~/.zshenv — never
# .zprofile, .zshrc or /usr/libexec/path_helper — so the Homebrew prefix is
# absent from PATH and mosh dies with "mosh-server: command not found" while
# plain ssh to the same host works. Fixing it client-side (--server=/path) has
# to be repeated in every client on every device; fixing it here is once.
#
# Keep this file tiny and free of side effects: it runs for every zsh script on
# the machine, so anything slow or interactive here is paid thousands of times.
# Interactive configuration belongs in config/zshrc.sh.

# Prepend a Homebrew prefix only when it exists and is not already present, so
# this stays idempotent across nested shells and never shadows a deliberate PATH.
for _brew_prefix in /opt/homebrew/bin /usr/local/bin /home/linuxbrew/.linuxbrew/bin; do
  [[ -d "$_brew_prefix" ]] || continue
  case ":$PATH:" in
    *":$_brew_prefix:"*) ;;
    *) export PATH="$_brew_prefix:$PATH" ;;
  esac
done
unset _brew_prefix
