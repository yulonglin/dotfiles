#!/usr/bin/env zsh
# shellcheck shell=bash
# Print resolved component states the way a REAL invocation resolves them —
# through parse_args and CLI flags — rather than through the PROFILE= env var.
#
# This exists because the two paths diverged and only the env one was tested.
# config.sh applies the default profile at source time; a CLI flag then
# re-applies a profile on top of that already-mutated state. A profile whose
# case body assumed the registry defaults were still live therefore produced a
# different (badly wrong) answer through flags than through the env var —
# --devbox gave 14 components instead of 50 — while every fixture passed.
#
# Usage: dump_components_cli.zsh <dotfiles-dir> [flags...]
emulate -L zsh
set -uo pipefail

DOT_DIR="${1:?usage: dump_components_cli.zsh <dotfiles-dir> [flags...]}"
shift
export DOT_DIR

DOTFILES_SKIP_LOCAL_CONFIG=1
export DOTFILES_SKIP_LOCAL_CONFIG

source "$DOT_DIR/config.sh" >/dev/null 2>&1
source "$DOT_DIR/scripts/shared/helpers.sh" >/dev/null 2>&1

# parse_args calls show_help for --help; stub it so it is never a live exit path.
show_help() { : }

parse_args "$@"

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
} | LC_ALL=C sort
