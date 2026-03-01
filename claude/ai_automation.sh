#!/usr/bin/env bash
set -euo pipefail

resolve_script_path() {
  local src="${BASH_SOURCE[0]}"
  while [[ -h "$src" ]]; do
    local dir
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ "$src" != /* ]] && src="$dir/$src"
  done
  printf '%s\n' "$(cd -P "$(dirname "$src")" && pwd)/$(basename "$src")"
}

# Resolve to real dotfiles path even when ~/.claude is a symlink.
this_file="$(resolve_script_path)"
this_dir="$(cd "$(dirname "$this_file")" && pwd)"
cfg="${this_dir}/../config/ai_automation.sh"

if [[ -f "$cfg" ]]; then
  # shellcheck disable=SC1090
  source "$cfg"
fi
