#!/usr/bin/env zsh
# Manually trigger secrets sync (SSH config, authorized_keys, git identity)
set -uo pipefail

DOT_DIR="$(cd "$(dirname "$(realpath "$0")")/.." && pwd)"
export DOT_DIR

source "$DOT_DIR/config.sh"
source "$DOT_DIR/scripts/shared/helpers.sh"

sync_secrets
