#!/usr/bin/env zsh
set -euo pipefail

REPO_ROOT="${0:A:h:h}"
DOT_DIR="$REPO_ROOT"
export DOT_DIR

source "$REPO_ROOT/config.sh"

array_contains() {
    local needle="$1"
    shift

    local item
    for item in "$@"; do
        [[ "$item" == "$needle" ]] && return 0
    done
    return 1
}

array_contains "watch" "${PACKAGES_MACOS[@]}" || {
    print -u2 "Expected PACKAGES_MACOS to include Homebrew formula: watch"
    exit 1
}
