#!/usr/bin/env bash
# shellcheck shell=bash
#
# SessionStart hook: trust the .envrc that .worktreeinclude copied into a worktree.
#
# Claude Code's `.worktreeinclude` copies .envrc into each new worktree, but direnv
# keys its allowlist on path + content hash, so the copy lands blocked and the
# session silently has no API keys.
#
# This only ever PROPAGATES an existing trust decision. Two conditions, and both
# are needed:
#
#   1. The copy is byte-identical to the main checkout's .envrc.
#   2. The main checkout's .envrc is ITSELF already allowed in direnv.
#
# Identity alone establishes provenance, not authorization. A main .envrc can be
# byte-identical and still unapproved — `setup-envrc` prints "Run manually:
# direnv allow" and continues when its own allow fails, so an unapproved main
# .envrc is a state that actually occurs. Approving the copy on identity alone
# would grant the worktree trust the original never had, which is an escalation
# rather than a propagation.
#
# Everything else is left blocked for the user to allow by hand.

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

# Is the main checkout's .envrc itself trusted? `direnv status` must be run FROM
# the main checkout: run from the worktree it would report the worktree's own
# copy. Verified against direnv 2.37.1, which prints:
#   Found RC path     <path to the .envrc for that directory>
#   Found RC allowed  <0 allowed | 1 not allowed | 2 denied>
#   Found RC allowPath <the allowlist file backing that decision>
main_state=$(cd "$main_checkout" && direnv status 2>/dev/null) || exit 0
found_path=$(printf '%s\n' "$main_state" | sed -n 's/^Found RC path //p' | head -n 1)
found_allowed=$(printf '%s\n' "$main_state" | sed -n 's/^Found RC allowed //p' | head -n 1)
allow_path=$(printf '%s\n' "$main_state" | sed -n 's/^Found RC allowPath //p' | head -n 1)

# Confirm we are reading the state of the file we actually compared against.
[[ "$found_path" == "$main_envrc" ]] || exit 0

# Require both the status code and the on-disk allowlist entry, so that a future
# change to direnv's enum fails closed (no auto-allow, user allows by hand)
# rather than open.
if [[ "$found_allowed" != "0" || -z "$allow_path" || ! -f "$allow_path" ]]; then
    echo "$main_envrc is not itself allowed in direnv — not propagating trust to $cwd." >&2
    echo "Allow the main checkout first: cd $main_checkout && direnv allow ." >&2
    exit 0
fi

if ! err=$(direnv allow "$cwd" 2>&1); then
    echo "direnv allow failed for $cwd: $err" >&2
fi

exit 0
