#!/usr/bin/env zsh
# shellcheck shell=bash
# Print the resolved INSTALL_/DEPLOY_ component states for one profile, sorted,
# one VAR=value per line. Used by tests/test_profile_defaults.sh to pin profile
# semantics across the standard-default flip. Only registry component variables
# are printed — never the identity/secret variables config.sh also carries.
#
# Usage: dump_components.zsh <profile> <dotfiles-dir>
emulate -L zsh
set -euo pipefail

PROFILE="${1:?usage: dump_components.zsh <profile> <dotfiles-dir>}"
DOT_DIR="${2:?usage: dump_components.zsh <profile> <dotfiles-dir>}"
export PROFILE DOT_DIR

# config.local.sh is a per-machine override; golden fixtures must not see it.
DOTFILES_SKIP_LOCAL_CONFIG=1
export DOTFILES_SKIP_LOCAL_CONFIG

source "$DOT_DIR/config.sh"

{
    for entry in "${INSTALL_REGISTRY[@]}"; do
        name="${entry%%|*}"
        var="INSTALL_${(U)name//-/_}"
        print -r -- "$var=${(P)var}"
    done
    for entry in "${DEPLOY_REGISTRY[@]}"; do
        name="${entry%%|*}"
        var="DEPLOY_${(U)name//-/_}"
        print -r -- "$var=${(P)var}"
    done
} | sort
