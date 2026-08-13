#!/usr/bin/env bash
# shellcheck shell=bash
#
# SessionStart hook: trust the .envrc that .worktreeinclude copied into a worktree.
#
# Claude Code's `.worktreeinclude` copies .envrc into each new worktree, but direnv
# keys its allowlist on path + content hash, so the copy lands blocked and the
# session silently has no API keys.
#
# This only ever PROPAGATES an existing trust decision: it allows the copy solely
# when the copy is byte-identical to the main checkout's .envrc. A worktree .envrc
# that has been edited — by a task, a merge, or anything else — is left blocked for
# the user to allow by hand. Auto-allowing an arbitrary .envrc would let any writer
# of that file execute shell at the next prompt.

set -euo pipefail

command -v direnv >/dev/null 2>&1 || exit 0

# SessionStart delivers JSON on stdin; `cwd` is the session directory. Fall back to
# PWD when stdin is not JSON (manual invocation, or a harness that omits the field).
payload=""
if [[ ! -t 0 ]]; then
    payload=$(cat 2>/dev/null || true)
fi

cwd=""
if [[ -n "$payload" ]]; then
    cwd=$(printf '%s' "$payload" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null || true)
fi
[[ -n "$cwd" ]] || cwd="$PWD"
[[ -d "$cwd" ]] || exit 0

# Only act inside a worktree, never in a main checkout.
git_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
common_dir=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[[ "$git_dir" != "$common_dir" ]] || exit 0   # main checkout — nothing to do

worktree_envrc="$cwd/.envrc"
[[ -f "$worktree_envrc" ]] || exit 0
[[ ! -L "$worktree_envrc" ]] || exit 0        # a symlink is not a copy we vouched for

main_checkout=$(dirname "$common_dir")
main_envrc="$main_checkout/.envrc"
[[ -f "$main_envrc" ]] || exit 0

if ! cmp -s "$main_envrc" "$worktree_envrc"; then
    echo "worktree .envrc differs from $main_envrc — left blocked. Allow it yourself: cd $cwd && direnv allow ." >&2
    exit 0
fi

if ! err=$(direnv allow "$cwd" 2>&1); then
    echo "direnv allow failed for $cwd: $err" >&2
fi

exit 0
